-module(rabbit_consumer_stress).

-export([main/1]).

-define(OPTIONS,
    [
    {type, $t, "type", {atom, network}, "Connection type."},
    {runs, $r, "runs", {integer, 10}, "Number of test runs."},
    {mode, $m, "mode", {atom, sync}, "Run mode. sync - run sequentially, async - run in parallel"},
    {interval, $i, "interval", {integer, 2000}, "Interval between starting parallel runs."},
    {connections, $c, "connections", {integer, 10}, "Number of connections"},
    {channels, $h, "channels", {integer, 10}, "Number of channels per connection"},
    {queues, $q, "queues", {integer, 10}, "Number of queues per channel"},
    {consumers, $k, "consumers", {integer, 2}, "Number of consumers per queue"},
    {sleep, $s, "sleep", {integer, 2000}, "Time to keep connection alive"},
    {node, $n, "node", atom, "Node name of tested broker node."},
    {report_memory, $M, "report_memory", {boolean, false}, "Report memory breakdown during run"}
    ]).

main(["-h"]) ->
    getopt:usage(?OPTIONS, "rabbit_consumer_stress");
main(Args) ->
    case getopt:parse(?OPTIONS, Args) of
        {ok, {Options, []}} ->
            run_test(Options);
        {ok, {_, Invalid}}  ->
            io:format("Invalid options ~p~n", [Invalid])
    end.

run_test(Options) ->
    Type = proplists:get_value(type, Options),
    Runs = proplists:get_value(runs, Options),
    Mode = proplists:get_value(mode, Options),
    Interval = proplists:get_value(interval, Options),
    Connections = proplists:get_value(connections, Options),
    Channels = proplists:get_value(channels, Options),
    Queues = proplists:get_value(queues, Options),
    Consumers = proplists:get_value(consumers, Options),
    Sleep = proplists:get_value(sleep, Options),
    Node = proplists:get_value(node, Options),
    ReportMemory = proplists:get_value(report_memory, Options),
    case {Type, Node} of
        {direct, undefined} ->
            io:format("~nDirect connections require node to be specified!~n~n"),
            getopt:usage(?OPTIONS, "rabbit_consumer_stress");
        _ ->
            rabbit_connection_churn:with_stats(
                Node, ReportMemory, Runs, Interval, Sleep, Mode, 
                Type, Connections, Channels, Queues, Consumers)
    end.



