# Naive RabbitMQ stress test tool

This repo contains two stress testing tools: 
 - Process creation tool
 - HTTP API tool

Process creation tool is used stress test creation of connections, channels, queues and consumers in rabbitmq broker.

HTTP API tool is used to measure HTTP API requests performance.

## Process creation tool

This tool uses erlang client to open connections, create channels, queues and consumers.

It creates connections, channels for each connection, queues for each channel 
and consumers for each queue, waits for `sleep` milliseconds and then closes connections.

The tool currently targets version `3.6.x`

## HTTP API tool

This tool is used to measure response time of HTTP API requests, that run in parallel.

It uses `gun` HTTP client to create parallel connections and execute requests.

# Usage

To build escript file run:

```
make escript
```

To show the tool usage:

Process creation tool:

```
./rabbit_consumer_stress -h
```

HTTP API tool:

```
./rabbit_http_stress -h
```

Test output will contain execution time statistics for series of test runs.

Memory report contains rabbitmq memory breakdown.


