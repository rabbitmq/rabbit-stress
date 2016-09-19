# Naive RabbitMQ consumer stress test tool

This tool is used to stress test consumer creation in rabbitmq broker.

It uses erlang client to open connections, create channels, queues and consumers.

The tool currently targets version `3.6.x`

# Usage

To build escript file run:

```
make escript
```

To show the tool usage:

```
./rabbit_consumer_stress -h
```

Test output will contain execution time statistics for series of test runs.

Memory report contains rabbitmq memory breakdown and ETS tables memory.


