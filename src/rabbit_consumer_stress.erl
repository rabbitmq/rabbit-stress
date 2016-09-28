-module(rabbit_consumer_stress).

-export([main/1]).

-define(OPTIONS,
    [
    {type, $t, "type", {atom, network}, "Connection type."},
    {runs, $r, "runs", {integer, 10}, "Number of test runs."},
    {mode, $m, "mode", {atom, sync}, "Run mode. sync - run sequentially, async - run in parallel"},
    {interval, $i, "interval", {integer, 2000}, "Interval between starting parallel runs."},
    {connections, $c, "connections", {integer, 10}, "Number of connections"},
    {channels, $C, "channels", {integer, 10}, "Number of channels per connection"},
    {queues, $q, "queues", {integer, 10}, "Number of queues per channel"},
    {consumers, $k, "consumers", {integer, 2}, "Number of consumers per queue"},
    {sleep, $s, "sleep", {integer, 2000}, "Time to keep connection alive"},
    {node, $n, "node", atom, "Node name of tested broker node."},
    {report_memory, $M, "report_memory", {boolean, false}, "Report memory breakdown during run"},
    {self_node_name, $N, "self_node_name", {atom, consimer_test}, "Name of the test node."},
    {host, $H, "host", {string, "localhost"}, "Host to connect to"},
    {port, $P, "port", {integer, 5672}, "Port to connect to"}
    ]).

main(["-h"]) ->
    getopt:usage(?OPTIONS, "rabbit_consumer_stress");
main(Args) ->
    case getopt:parse(?OPTIONS, Args) of
        {ok, {Options, []}} ->
            run_test(Options);
        {ok, {_, Invalid}}  ->
            io:format("Invalid options ~p~n"
                      "Run 'rabbit_consumer_stress -h' to see available options~n",
                      [Invalid])
    end.

run_test(Options) ->
    Type = proplists:get_value(type, Options),
    Runs = proplists:get_value(runs, Options),
    SyncMode = proplists:get_value(mode, Options),
    Interval = proplists:get_value(interval, Options),
    Connections = proplists:get_value(connections, Options),
    Channels = proplists:get_value(channels, Options),
    Queues = proplists:get_value(queues, Options),
    Consumers = proplists:get_value(consumers, Options),
    Sleep = proplists:get_value(sleep, Options),
    Node = proplists:get_value(node, Options),
    ReportMemory = proplists:get_value(report_memory, Options),
    SelfNodeName = proplists:get_value(self_node_name, Options),
    Host = proplists:get_value(host, Options),
    Port = proplists:get_value(port, Options),
    rabbit_stress:start_distribution(SelfNodeName),
    case {Type, Node} of
        {direct, undefined} ->
            io:format("~nDirect connections require node to be specified!~n~n"),
            getopt:usage(?OPTIONS, "rabbit_consumer_stress");
        _ ->
            TestFun = fun() ->
                rabbit_churn:with_stats(
                    #{
                        node => Node,
                        runs => Runs,
                        interval => Interval,
                        sleep => Sleep,
                        sync_mode => SyncMode,
                        connection_type => Type,
                        connections => Connections,
                        channels => Channels,
                        queues => Queues,
                        consumers => Consumers,
                        host => Host,
                        port => Port
                    })
            end,
            case ReportMemory of
                true  ->
                    rabbit_stress:with_memory(Node, round(Interval * Runs / 2), TestFun);
                false ->
                    TestFun()
            end
    end.



