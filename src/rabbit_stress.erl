-module(rabbit_stress).

-export([main/1, start_distribution/1]).
-export([with_memory/4, report_memory/3]).

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

start_distribution(undefined) ->
    Candidate = "stress_test_" ++ integer_to_list(rand:uniform(100000)),
    case start_distribution(list_to_atom(Candidate)) of
        {ok, _} = OK -> OK;
        _            -> start_distribution(undefined)
    end;
start_distribution(NodeName) ->
    net_kernel:start([NodeName, shortnames]).

with_memory(undefined, _, TestFun, _) -> TestFun();
with_memory(Node, Time, TestFun, Verbose) ->
    io:format("Reporting memory from node ~p~n~n", [Node]),
    MemCollector = memory_collector(),
    {ok, MemInterval} = timer:apply_interval(
        Time, rabbit_stress, report_memory, [Node, MemCollector, Verbose]),
    Result = TestFun(),
    {ok, cancel} = timer:cancel(MemInterval),
    report_memory_collector(MemCollector, Verbose),
    Result.

report_memory(Node, MemCollector, Verbose) ->
    memory_report(Node, MemCollector, Verbose),
    % io:format("ETS_TABLES:~n"),
    % ets_report(Node),
    ok.

% ets_report(Node) ->
%     [io:format("~p:" ++
%                [" " || _ <- lists:seq(1, 50 - length(atom_to_list(K)))] ++
%                " ~.2f Mb~n", [K, V/1000000])
%      || {K,V} <- rpc:call(Node, rabbit_vm, ets_tables_memory, [[all]])].

memory_report(Node, MemCollector, Verbose) ->
    Mem = rpc:call(Node, rabbit_vm,memory, []),
    MemCollector ! {memory, Mem},
    case Verbose of
        true ->
            io:format("MEMORY: ~n"),
            [io:format("~p:" ++
                       [" " || _ <- lists:seq(1, 22 - length(atom_to_list(K)))] ++
                       " ~.2f Mb~n", [K, V/1000000])
             || {K,V} <- Mem];
        false -> ok
    end.

memory_collector() ->
    spawn_link(fun() -> memory_collector([]) end).

report_memory_collector(MemCollector, Verbose) ->
    MemCollector ! {report, self()},
    receive {memory_report, Mems} ->
        Aggr = aggregate_memory_collection(Mems),
        case Verbose of
            true  -> io:format("Memory stats ~p~n", [Aggr]);
            false -> ok
        end,
        lists:foreach(
            fun(Item) ->
                Breakdown = [{K, proplists:get_value(Item, V)} || {K, V} <- Aggr],
                io:format("~s:~n", [Item]),
                print_breakdown(Breakdown, length(atom_to_list(Item)) + 1)
            end,
            [min, max, avg])
    after 1000                    -> error(no_memory_report_from_collector)
    end.

aggregate_memory_collection([]) ->
    io:format("No memory reports ~n");
aggregate_memory_collection([Mem | Rest]) ->
    {Columns, FirstRow} = lists:unzip(Mem),
    Rows = [ V || M <- Rest, {_, V} <- [lists:unzip(M)] ],
    Stats = merge_rows(Columns, [FirstRow | Rows], []),
    lists:map(
        fun({Col, Vals}) ->
            {Col, aggregate(Vals)}
        end,
        Stats).

print_breakdown(Breakdown, Skip) ->
    [io:format(lists:duplicate(Skip, $ ) ++ "~p:" ++
               [" " || _ <- lists:seq(1, 22 - length(atom_to_list(K)))] ++
               " ~.2f Mb~n", [K, V/1000000])
     || {K,V} <- Breakdown].

merge_rows([], _, Acc) -> Acc;
merge_rows([Column | Columns], Rows, Acc) ->
    {Heads, Tails} = lists:unzip([ {H, T} || [H | T] <- Rows ]),
    merge_rows(Columns, Tails, [{Column, Heads} | Acc]).

aggregate(Vals) ->
    Length = length(Vals),
    Avg = lists:sum(Vals) / Length,
    Sorted = lists:sort(Vals),

    Mean = lists:nth(round(0.5 * Length), Sorted),
    Per75 = lists:nth(round(0.75 * Length), Sorted),
    Per90 = lists:nth(round(0.9 * Length), Sorted),
    Per95 = lists:nth(round(0.95 * Length), Sorted),
    Max = lists:max(Sorted),
    Min = lists:min(Sorted),

    [{avg, Avg},
     {mean, Mean},
     {per75, Per75},
     {per90, Per90},
     {per95, Per95},
     {max, Max},
     {min, Min}].

memory_collector(Acc) ->
    receive
        {memory, Mem} -> memory_collector([Mem | Acc]);
        {report, Pid} -> Pid ! {memory_report, Acc}
    end.

