-module(rabbit_churn).
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
            amqp_channel:call(Ch, #'basic.qos'{prefetch_count = 1}),
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

create_n_consumers(Count, Channel, QueueName, ConsumeInterval) ->
    n_items(Count,
        fun() ->
            Pid = spawn_link(fun() -> consumer_loop(Channel, ConsumeInterval) end),
            
            #'basic.consume_ok'{consumer_tag = Tag} =
                amqp_channel:subscribe(Channel,
                                       #'basic.consume'{queue = QueueName},
                                       Pid),
            Tag
        end).

consumer_loop(Channel, ConsumeInterval) ->
    timer:sleep(ConsumeInterval),
    receive
        #'basic.consume_ok'{} ->
          consumer_loop(Channel, ConsumeInterval);
        #'basic.cancel_ok'{} ->
          ok;
        {#'basic.deliver'{delivery_tag = DTag}, _Content} ->
          amqp_channel:call(Channel, #'basic.ack'{delivery_tag = DTag}),
          consumer_loop(Channel, ConsumeInterval)
    end.

close_consumers(ConsumerTags, _Channel) ->
    lists:map(
        fun(_Tag) ->
ok
            %amqp_channel:call(Channel, #'basic.cancel'{consumer_tag = Tag})
        end,
        ConsumerTags).

delete_queues(Queues, Channel) ->
    lists:map(
        fun(Q) ->
            try amqp_channel:call(Channel, #'queue.purge'{queue = Q})
	    catch _:_ -> ok
            end
        end,
        Queues).

close_connections(Connections) ->
    lists:map(
        fun(Conn) ->
            amqp_connection:close(Conn)
        end,
        Connections).

generate_queue_name(_Channel) ->
    list_to_binary("queue" ++
                   integer_to_list(rand:uniform(1000))).

with_stats(#{runs := Runs,
             interval := Interval,
             sleep := Sleep,
             sync_mode := SyncMode,
             connection_type := ConnectionType,
             connections := Connections,
             channels := Channels,
             queues := Queues,
             consumers := Consumers } = Config) ->
    SyncMsg = case SyncMode of
        sync  -> "sequentially";
        async -> "in parallel"
    end,
    io:format(
        "START TEST For ~p runs ~s with ~p ms interval~n"
        "Starting ~p connections x ~p channels x ~p queues x ~p consumers~n"
        "waiting for ~p for each run~n"
        "Connection type: ~p~n",
        [Runs, SyncMsg, Interval,
        Connections, Channels, Queues, Consumers,
        Sleep,
        ConnectionType]),

    Raw = start_test(Config),
    io:format("END TEST~n"),

    Avg = lists:sum(Raw) / Runs,
    Sorted = lists:sort(Raw),

    Mean = lists:nth(round(0.5 * Runs), Sorted),
    Per75 = lists:nth(round(0.75 * Runs), Sorted),
    Per90 = lists:nth(round(0.9 * Runs), Sorted),
    Per95 = lists:nth(round(0.95 * Runs), Sorted),
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

start_test(#{node := Node,
             runs := Runs,
             interval := Interval,
             sleep := Sleep,
             sync_mode := SyncMode,
             connection_type := ConnectionType,
             connections := NConnections,
             channels := NChannels,
             queues := NQueues,
             consumers := NConsumers,
             producers := NProducers,
             publish_interval := PublishInterval,
             consume_interval := ConsumeInterval,
             host := Host,
             port := Port }) ->
    ConnectionParams = case ConnectionType of
        direct  -> #amqp_params_direct{node = Node};
        network -> #amqp_params_network{host = Host, port = Port}
    end,
    Pids = n_items(Runs,
        fun(Index) ->
            Fun = fun() ->
                Conns = open_n_connections(NConnections, ConnectionParams),
                ConnChannels = lists:map(
                    fun(Conn) ->
                        Channels = open_n_channels(NChannels, Conn),
                        ChannelQueues = lists:map(
                            fun(Chan) ->
                                Queues = create_n_queues(NQueues, Chan),
                                Conss = lists:map(
                                    fun(Q) ->
                                        Producers = create_n_producers(NProducers, Chan, Q, PublishInterval),
                                        Consumers = create_n_consumers(NConsumers, Chan, Q, ConsumeInterval),
                                        {Producers, Consumers}
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
                                    fun({Prod, Cons}) ->
                                        stop_producers(Prod),
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
            case SyncMode of
                async ->
                    Pid = spawn_link(fun() ->
                        Self ! {self(), timer:tc(Fun)},
                        io:format(".~p.", [Index])
                    end),
                    timer:sleep(Interval),
                    Pid;
                sync  ->
                    Self ! {none, timer:tc(Fun)},
                    io:format("..~p..", [Index]),
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

create_n_producers(N, Chan, Queue, Interval) ->
    n_items(N, fun() ->
        spawn_link(fun() ->
            send_message(Chan, Queue),
            producer_loop(Chan, Queue, Interval)
        end)
    end).

producer_loop(Chan, Queue, Interval) ->
    receive
        stop -> ok
    after Interval ->
        send_message(Chan, Queue),
        producer_loop(Chan, Queue, Interval)
    end.

send_message(Chan, Queue) ->
    Msg = list_to_binary("message" ++ erlang:ref_to_list(make_ref())),
    amqp_channel:call(Chan,
                      #'basic.publish'{routing_key = Queue},
                      #amqp_msg{payload = Msg}).

stop_producers(Prods) ->
    lists:map(fun(P) -> P ! stop end, Prods).

n_items(Count, Fn) ->
    lists:map(fun(Index) ->
        case erlang:fun_info(Fn, arity) of
            {arity, 0} -> Fn();
            {arity, 1} -> Fn(Index)
        end
    end,
    lists:seq(1, Count)).

select_some(List) ->
    select_some(List, 0.5).

select_some(List, Fraction) ->
    lists:filter(fun(_) -> rand:uniform() > Fraction end, List).


