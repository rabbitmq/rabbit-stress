-module(rabbit_http_stress).

-export([main/1]).

-define(OPTIONS, [
    {host, $H, "url", {string, "localhost"}, "HTTP host to connect to."},
    {port, $P, "port", {integer, 15672}, "Port to connect to."},
    {total_requests, $r, "total_requests", {integer, 1000}, "Total number of requests for each target"},
    {parallel, $p, "parallel", {integer, 5}, "Number of requests for each target to run in parallel"},
    {report_memory, $M, "report_memory", {boolean, false}, "Report memory breakdown during run"},
    {node, $n, "node", atom, "Node name of tested broker node. Required to report memory"},
    {self_node_name, $N, "self_node_name", {atom, http_test}, "Name of the test node."}
]).


main(["-h"]) ->
    getopt:usage(?OPTIONS, "rabbit_http_stress");
main(Args) ->
    case getopt:parse(?OPTIONS, Args) of
        {ok, {Options, []}} ->
            run_test(Options);
        {ok, {_, Invalid}}  ->
            io:format("Invalid options ~p~n"
                      "Run 'rabbit_http_stress -h' to see available options~n",
                      [Invalid])
    end.

run_test(Options) ->
    Host = proplists:get_value(host, Options),
    Port = proplists:get_value(port, Options),
    Total = proplists:get_value(total_requests, Options),
    Parallel = proplists:get_value(parallel, Options),
    Node = proplists:get_value(node, Options),
    ReportMemory = proplists:get_value(report_memory, Options),
    SelfNode = proplists:get_value(self_node_name, Options),
    rabbit_stress:start_distribution(SelfNode),

    TestFun = fun() -> http_api_measure:start_test(Host, Port, Total, Parallel) end,
    case ReportMemory of
        true  ->
            rabbit_stress:with_memory(Node, 5000, TestFun);
        false ->
            TestFun()
    end.

