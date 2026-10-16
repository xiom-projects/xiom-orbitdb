// XIOM ORBITDB -- BENCH-1 cross-engine driver (bbolt side).
// Copyright (c) 2026 Eleftherios Notas and The XIOM Authors
// SPDX-License-Identifier: MIT OR Apache-2.0
//
// Mirrors tests/probes/probe_ycsb.xi (orbitdb) and the generated SQLite
// phase scripts: same op stream, same phases, same output lines, so
// scripts/bench_cross.{ps1,sh} can interleave the three engines.
//
// Build (Windows):  go build -o bin\bbolt-bench.exe .
// Build (WSL):      GOOS=linux GOARCH=amd64 go build -o bin/bbolt-bench-linux-amd64 .
//
// Output (parsed by the runner):
//   ycsb bbolt <phase> n=<ops> ms=<ms> ops_s=<ops*1000/ms>
//   ycsb bbolt verify count=<count> ok=<0|1>
//   ycsb bbolt done ok=<0|1> v=8|100 batch=<b> sync=<0|1>
package main

import (
	"encoding/binary"
	"flag"
	"fmt"
	"os"
	"time"

	bolt "go.etcd.io/bbolt"
)

var (
	flagFile    = flag.String("file", "", "db path (required)")
	flagN       = flag.Int("n", 50000, "key count (keys 0..n-1)")
	flagValsize = flag.Int("valsize", 8, "value bytes: 8 or 100")
	flagSync    = flag.Bool("sync", true, "durable (fsync) at commit acks")
	flagBatch   = flag.Int("batch", 1, "ops per commit group (1 = per-op)")
	flagPhase   = flag.String("phase", "all", "all|load|read|update|scan|delete")
	flagSeed    = flag.Int64("seed", 12345, "LCG seed")
	flagScans   = flag.Int("scans", 0, "scan count (default n/100)")
	flagDeletes = flag.Int("deletes", 0, "delete count (default n/10)")
)

var bucket = []byte("kv")

type lcg struct{ s int64 }

// Same stream as every other engine in BENCH-1.
func (r *lcg) next() int64 {
	r.s = (r.s*1103515245 + 12345) % 2147483648
	return r.s
}

func be64(v uint64) []byte {
	b := make([]byte, 8)
	binary.BigEndian.PutUint64(b, v)
	return b
}

func pad8(k int64) []byte {
	return []byte(fmt.Sprintf("%08d", k))
}

// Value bytes: v=8 -> BE64(key*7+1); v=100 -> pad8(key)+92 'x'.
func makeValue(k int64, valsize int) []byte {
	if valsize == 8 {
		return be64(uint64(k*7 + 1))
	}
	v := make([]byte, 100)
	copy(v, pad8(k))
	for i := 8; i < 100; i++ {
		v[i] = 'x'
	}
	return v
}

func report(phase string, n int, ms int64) {
	ops := int64(0)
	if ms > 0 {
		ops = int64(n) * 1000 / ms
	}
	fmt.Printf("ycsb bbolt %s n=%d ms=%d ops_s=%d\n", phase, n, ms, ops)
}

func fatalf(format string, a ...any) {
	fmt.Fprintf(os.Stderr, "ycsb bbolt: "+format+"\n", a...)
	os.Exit(1)
}

func main() {
	flag.Parse()
	if *flagFile == "" {
		fatalf("-file is required")
	}
	if *flagValsize != 8 && *flagValsize != 100 {
		fatalf("-valsize must be 8 or 100")
	}
	if *flagBatch < 1 {
		fatalf("-batch must be >= 1")
	}
	n := *flagN
	if n < 200 {
		fatalf("-n must be >= 200")
	}
	scans := *flagScans
	if scans == 0 {
		scans = n / 100
	}
	deletes := *flagDeletes
	if deletes == 0 {
		deletes = n / 10
	}

	db, err := bolt.Open(*flagFile, 0600, &bolt.Options{Timeout: 5 * time.Second})
	if err != nil {
		fatalf("open: %v", err)
	}
	defer db.Close()
	if !*flagSync {
		db.NoSync = true
	}

	// ---- load: sequential keys, batch groups ----
	if *flagPhase == "all" || *flagPhase == "load" {
		t0 := time.Now()
		var txerr error
		for lo := 0; lo < n; lo += *flagBatch {
			hi := lo + *flagBatch
			if hi > n {
				hi = n
			}
			txerr = db.Update(func(tx *bolt.Tx) error {
				b, err := tx.CreateBucketIfNotExists(bucket)
				if err != nil {
					return err
				}
				for k := lo; k < hi; k++ {
					if err := b.Put(be64(uint64(k)), makeValue(int64(k), *flagValsize)); err != nil {
						return err
					}
				}
				return nil
			})
			if txerr != nil {
				break
			}
		}
		ms := time.Since(t0).Milliseconds()
		if txerr != nil {
			fatalf("load: %v", txerr)
		}
		report("load", n, ms)
	}

	// ---- read: n point reads, fresh LCG stream ----
	if *flagPhase == "all" || *flagPhase == "read" {
		r := &lcg{s: *flagSeed}
		var sink uint64
		t0 := time.Now()
		readErr := db.View(func(tx *bolt.Tx) error {
			b := tx.Bucket(bucket)
			if b == nil {
				return fmt.Errorf("bucket missing")
			}
			for i := 0; i < n; i++ {
				key := r.next() % int64(n)
				v := b.Get(be64(uint64(key)))
				if len(v) > 0 {
					sink += uint64(v[0])
				}
			}
			return nil
		})
		ms := time.Since(t0).Milliseconds()
		if readErr != nil {
			fatalf("read: %v", readErr)
		}
		_ = sink
		report("read", n, ms)
	}

	// ---- update: same values (idempotent), batch groups ----
	if *flagPhase == "all" || *flagPhase == "update" {
		r := &lcg{s: *flagSeed}
		t0 := time.Now()
		var txerr error
		done := 0
		for done < n {
			hi := done + *flagBatch
			if hi > n {
				hi = n
			}
			keys := make([]int64, 0, hi-done)
			for i := done; i < hi; i++ {
				keys = append(keys, r.next()%int64(n))
			}
			txerr = db.Update(func(tx *bolt.Tx) error {
				b := tx.Bucket(bucket)
				if b == nil {
					return fmt.Errorf("bucket missing")
				}
				for _, k := range keys {
					if err := b.Put(be64(uint64(k)), makeValue(k, *flagValsize)); err != nil {
						return err
					}
				}
				return nil
			})
			if txerr != nil {
				break
			}
			done = hi
		}
		ms := time.Since(t0).Milliseconds()
		if txerr != nil {
			fatalf("update: %v", txerr)
		}
		report("update", n, ms)
	}

	// ---- scan: scans x 100 consecutive keys ----
	if (*flagPhase == "all" || *flagPhase == "scan") && *flagValsize == 8 {
		r := &lcg{s: *flagSeed}
		var sink uint64
		t0 := time.Now()
		scanErr := db.View(func(tx *bolt.Tx) error {
			b := tx.Bucket(bucket)
			if b == nil {
				return fmt.Errorf("bucket missing")
			}
			c := b.Cursor()
			for s := 0; s < scans; s++ {
				start := r.next() % int64(n-100)
				count := 0
				for k, v := c.Seek(be64(uint64(start))); k != nil && count < 100; k, v = c.Next() {
					if len(v) > 0 {
						sink += uint64(v[0])
					}
					count++
				}
			}
			return nil
		})
		ms := time.Since(t0).Milliseconds()
		if scanErr != nil {
			fatalf("scan: %v", scanErr)
		}
		_ = sink
		report("scan", scans, ms)
	}

	// ---- delete: distinct keys via bitmap, batch groups ----
	deletedDistinct := 0
	ranDeletes := false
	if (*flagPhase == "all" || *flagPhase == "delete") && *flagValsize == 8 {
		ranDeletes = true
		r := &lcg{s: *flagSeed}
		marked := make([]bool, n)
		t0 := time.Now()
		var txerr error
		done := 0
		// own fresh stream at seed (all engines delete from their own stream)
		for done < deletes {
			hi := done + *flagBatch
			if hi > deletes {
				hi = deletes
			}
			batchKeys := make([]int64, 0, hi-done)
			for i := done; i < hi; i++ {
				k := r.next() % int64(n)
				batchKeys = append(batchKeys, k)
				if !marked[k] {
					marked[k] = true
					deletedDistinct++
				}
			}
			txerr = db.Update(func(tx *bolt.Tx) error {
				b := tx.Bucket(bucket)
				if b == nil {
					return fmt.Errorf("bucket missing")
				}
				for _, k := range batchKeys {
					if err := b.Delete(be64(uint64(k))); err != nil {
						return err
					}
				}
				return nil
			})
			if txerr != nil {
				break
			}
			done = hi
		}
		ms := time.Since(t0).Milliseconds()
		if txerr != nil {
			fatalf("delete: %v", txerr)
		}
		report("delete", deletes, ms)
	}

	// ---- verify ----
	want := n
	if ranDeletes {
		want = n - deletedDistinct
	}
	count := 0
	verr := db.View(func(tx *bolt.Tx) error {
		b := tx.Bucket(bucket)
		if b == nil {
			return fmt.Errorf("bucket missing")
		}
		return b.ForEach(func(k, v []byte) error {
			count++
			return nil
		})
	})
	if verr != nil {
		fatalf("verify: %v", verr)
	}
	ok := 0
	if count == want {
		ok = 1
	}
	fmt.Printf("ycsb bbolt verify count=%d ok=%d\n", count, ok)

	syncInt := 0
	if *flagSync {
		syncInt = 1
	}
	fmt.Printf("ycsb bbolt done ok=%d v=%d batch=%d sync=%d\n", ok, *flagValsize, *flagBatch, syncInt)
	if ok != 1 {
		os.Exit(1)
	}
}
