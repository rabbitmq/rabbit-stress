#!/usr/bin/env bash

connections=$1
batches=`expr $connections / 20 - 1`
runs=$2

["x" = "x$runs"] && runs=10

for i in `seq 1 $batches`; do
    ./rabbit_consumer_stress -c 20 -C 4 -m sync -r 50 -I 5000 -k 5 -K 100 -P 5673 &
done
./rabbit_consumer_stress -c 20 -C 4 -m sync -r 50 -P 5673 -I 5000 -k 5 -K 100 -n rabbit1@ubuntu -M -R 20000 &

for i in `seq 1 $batches`; do
    ./rabbit_consumer_stress -c 20 -C 4 -m sync -r 50 -P 5674 -I 5000 -k 5 -K 100 &
done
./rabbit_consumer_stress -c 20 -C 4 -m sync -r 50 -P 5674 -n rabbit2@ubuntu -M -R 20000 -I 5000 -k 5 -K 100 &


for i in `seq 1 $batches`; do
    ./rabbit_consumer_stress -c 20 -C 4 -m sync -r 50  -I 5000 -k 5 -K 100 &
done
./rabbit_consumer_stress -c 20 -C 4 -m sync -r 50 -n rabbit@ubuntu -M -R 20000 -I 5000 -k 5 -K 100 


