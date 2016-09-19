-module(rabbit_connection_churn).
-include_lib("amqp_client/include/amqp_client.hrl").
-compile(export_all).

open_n_connections(Count, Params) ->
    n_items(Count,
        fun() ->
            {ok, C} = amqp_connection:start(Params),
            C
        end).

open_n_channels(Count, Connection) ->
    n_items(Count,
        fun() ->
            {ok, Ch} = amqp_connection:open_channel(Connection),
            Ch
        end).

create_n_queues(Count, Channel) ->
    n_items(Count,
        fun() ->
            QueueName = generate_queue_name(Channel),
            #'queue.declare_ok'{queue = QueueName} =
                amqp_channel:call(Channel, #'queue.declare'{queue = QueueName}),
            QueueName
        end).

create_n_consumers(Count, Channel, QueueName) ->
    n_items(Count,
        fun() ->
            #'basic.consume_ok'{consumer_tag = Tag} =
                amqp_channel:call(Channel, #'basic.consume'{queue = QueueName}),
            Tag
        end).

close_consumers(ConsumerTags, Channel) ->
    lists:map(
        fun(Tag) ->
            amqp_channel:call(Channel, #'basic.cancel'{consumer_tag = Tag})
        end,
        ConsumerTags).

delete_queues(Queues, Channel) ->
    lists:map(
        fun(Q) ->
            amqp_channel:call(Channel, #'queue.delete'{queue = Q})
        end,
        Queues).

close_connections(Connections) ->
    lists:map(
        fun(Conn) ->
            amqp_connection:close(Conn)
        end,
        Connections).

generate_queue_name(Channel) ->
    list_to_binary("queue" ++
                   pid_to_list(Channel) ++
                   integer_to_list(rand:uniform(1000000))).

with_stats(Node, ReportMemory, Loops, Interval, Sleep, Mode, ConnectionType, Nc, Nch, Nq, Ncon) ->
    io:format(
        "START TEST For ~p loops with ~pms interval~n"
        "Starting ~p connections, ~p channels, ~p queues and ~p consumers~n"
        "witing for ~p for each consumer~n",
        [Loops, Interval, Nc, Nch, Nq, Ncon, Sleep]),
    ConnectionParams = case ConnectionType of
        direct  -> #amqp_params_direct{node = Node};
        network -> #amqp_params_network{}
    end,
    TestFun = fun() ->
        start_test(Loops, Interval, Sleep, Mode, ConnectionParams, Nc, Nch, Nq, Ncon)
    end,
    Raw = case ReportMemory of
        true  ->
            with_memory(Node, round(Interval * Loops / 10), TestFun);
        false ->
            TestFun()
    end,
    io:format("END TEST~n"),

    Avg = lists:sum(Raw) / Loops,
    Sorted = lists:sort(Raw),

    Mean = lists:nth(round(0.5 * Loops), Sorted),
    Per75 = lists:nth(round(0.75 * Loops), Sorted),
    Per90 = lists:nth(round(0.9 * Loops), Sorted),
    Per95 = lists:nth(round(0.95 * Loops), Sorted),
    Max = lists:max(Sorted),
    Min = lists:min(Sorted),

    Stats = [{avg, Avg},
     {mean, Mean},
     {per75, Per75},
     {per90, Per90},
     {per95, Per95},
     {max, Max},
     {min, Min}],
    io:format("STATS ~p~n", [Stats]).

with_memory(undefined, _, TestFun) -> TestFun();
with_memory(Node, Time, TestFun) ->
    {ok, MemInterval} = timer:apply_interval(
        Time, rabbit_connection_churn, report_memory, [Node]),
    Result = TestFun(),
    {ok, cancel} = timer:cancel(MemInterval),
    Result.

report_memory(Node) ->
    io:format("MEMORY ~p~n", [rpc:call(Node, rabbit_vm, memory, [])]),
    io:format("ETS_TABLES ~p~n", [rpc:call(Node, rabbit_vm, ets_tables_memory, [all])]).

start_test(Loops, Interval, Sleep, Mode, ConnectionParams, Nc, Nch, Nq, Ncon) ->
    Pids = n_items(Loops,
        fun() ->
            Fun = fun() ->
                Conns = open_n_connections(Nc, ConnectionParams),
                ConnChannels = lists:map(
                    fun(Conn) ->
                        Channels = open_n_channels(Nch, Conn),
                        ChannelQueues = lists:map(
                            fun(Chan) ->
                                Queues = create_n_queues(Nq, Chan),
                                Conss = lists:map(
                                    fun(Q) ->
                                        create_n_consumers(Ncon, Chan, Q)
                                    end,
                                    Queues),
                                {Chan, Queues, Conss}
                            end,
                            Channels),
                        ChannelQueues
                    end,
                    Conns),
                timer:sleep(Sleep),

                lists:map(
                    fun(ChannelQueues) ->
                        lists:map(
                            fun({Chan, Queues, Conss}) ->
                                lists:map(
                                    fun(Cons) ->
                                        close_consumers(select_some(Cons), Chan)
                                    end,
                                    Conss),
                                
                                delete_queues(Queues, Chan)
                            end,
                            ChannelQueues),
                        lists:map(
                            fun({Chan, _, _}) ->
                                amqp_channel:close(Chan)
                            end,
                            ChannelQueues)
                    end,
                    ConnChannels),
                close_connections(Conns)
            end,
            Self = self(),
            case Mode of
                async ->
                    Pid = spawn_link(fun() ->
                        Self ! {self(), timer:tc(Fun)},
                        io:format(".")
                    end),
                    timer:sleep(Interval),
                    Pid;
                sync  ->
                    Self ! {none, timer:tc(Fun)},
                    io:format("."),
                    none
            end
        end),
    io:format("~n"),
    ConstTime = Sleep * 1000,
    lists:map(
        fun(Pid) ->
            receive {Pid, {Time, _}} ->
                Time - ConstTime
            after 1000000 ->
                exit(timeout_waiting_for_test)
            end
        end,
        Pids).


n_items(Count, Fn) ->
    lists:map(fun(_) -> Fn() end,
              lists:seq(1, Count)).

select_some(List) ->
    lists:filter(fun(_) -> rand:uniform() > 0.5 end, List).


