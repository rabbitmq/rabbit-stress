-module(rabbit_stress).

-export([main/1, start_distribution/1]).
-export([with_memory/3, report_memory/1]).

main(Args) ->
    case script_name() of
        "rabbit_consumer_stress" ->
            rabbit_consumer_stress:main(Args);
        "rabbit_http_stress" ->
            rabbit_http_stress:main(Args);
        Other ->
            io:format("Unknown sctipt ~p~n", [Other])
    end.

script_name() ->
    filename:basename(escript:script_name(), ".escript").

start_distribution(NodeName) ->
    net_kernel:start([NodeName, shortnames]).

with_memory(undefined, _, TestFun) -> TestFun();
with_memory(Node, Time, TestFun) ->
    io:format("Reporting memory from node ~p~n~n", [Node]),
    {ok, MemInterval} = timer:apply_interval(
        Time, rabbit_stress, report_memory, [Node]),
    Result = TestFun(),
    {ok, cancel} = timer:cancel(MemInterval),
    Result.

report_memory(Node) ->
    io:format("MEMORY: ~n"),
    memory_report(Node),
    % io:format("ETS_TABLES:~n"),
    % ets_report(Node),
    ok.

% ets_report(Node) ->
%     [io:format("~p:" ++
%                [" " || _ <- lists:seq(1, 50 - length(atom_to_list(K)))] ++
%                " ~.2f Mb~n", [K, V/1000000])
%      || {K,V} <- rpc:call(Node, rabbit_vm, ets_tables_memory, [[all]])].

memory_report(Node) ->
    [io:format("~p:" ++
               [" " || _ <- lists:seq(1, 22 - length(atom_to_list(K)))] ++
               " ~.2f Mb~n", [K, V/1000000])
     || {K,V} <- rpc:call(Node, rabbit_vm,memory, [])].
