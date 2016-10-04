-module(http_api_measure).

-compile(export_all).

% Very long http timeout
-define(TIMEOUT, 1000000).

prepare() ->
    inets:start(),
    application:ensure_all_started(gun).

start_test(Host, Port, Total, Parallel) ->
    prepare(),
    Requests = ["/api/queues", "/api/channels", "/api/connections"],
    RequestPlans = gen_request_plans(Host, Port, Total, Parallel, Requests),
    lists:foreach(
        fun({T, P, Q} = Plan) ->
            io:format("Executing ~p requests for query ~p with ~p parallel processes.~n",
                      [T, Q, P]),
            Result = run_plan(Plan),
            format_report(Plan, Result)
        end,
        RequestPlans).

format_report({Requests, _, _}, Result) ->
    Raw = [ round(Time) || Time <- Result ],
    Avg = lists:sum(Raw) / Requests,
    Sorted = lists:sort(Raw),
    Mean = lists:nth(round(0.5 * Requests), Sorted),
    Per75 = lists:nth(round(0.75 * Requests), Sorted),
    Per90 = lists:nth(round(0.9 * Requests), Sorted),
    Per95 = lists:nth(round(0.95 * Requests), Sorted),
    Max = lists:max(Sorted),
    Min = lists:min(Sorted),

    Stats = [{avg, Avg},
     {mean, Mean},
     {per75, Per75},
     {per90, Per90},
     {per95, Per95},
     {max, Max},
     {min, Min}],

    io:format("~nTime statistics ~p~n", [Stats]).

gen_request_plans(Host, Port, Total, Parallel, Requests) ->
    [{Total, Parallel, {Host, Port, Req}} || Req <- Requests].

run_plan({Total, Parallel, Req}) ->
    Pid = self(),
    [ request_proc(Req, Pid) || _ <- lists:seq(1, Parallel) ],
    plan_loop(Total, 0, []).

request_proc(Req, Pid) ->
    spawn_link(fun() ->
        request_loop(Req, Pid)
    end).

request_loop({Host, Port, Path} = Req, Pid) ->
    Pid ! {request, self()},
    receive
        next ->
            {ok, ConnPid} = gun:open(Host, Port),
            gun:await_up(ConnPid),
            {Time, _} = timer:tc(fun() ->
                StreamRef = gun:get(ConnPid, Path, [{<<"authorization">>, "Basic Z3Vlc3Q6Z3Vlc3Q="}]),
                case gun:await(ConnPid, StreamRef, ?TIMEOUT) of
                        {response, fin, _Status, _Headers} ->
                                no_data;
                        {response, nofin, _Status, _Headers} ->
                                {ok, _} = gun:await_body(ConnPid, StreamRef, ?TIMEOUT)
                end,
                gun:flush(StreamRef),
                gun:cancel(ConnPid, StreamRef)
            end),
            gun:shutdown(ConnPid),
            Pid ! {done, Time},
            io:format("."),
            request_loop(Req, Pid);
        done ->
            ok
    end.

plan_loop(0, 0, Done) ->
    receive
        {request, Pid} ->
            Pid ! done,
            plan_loop(0, 0, Done)
    after 100 ->
        Done
    end;
plan_loop(Planned, Waiting, Done) ->
    receive
        {done, Time} ->
            plan_loop(Planned, Waiting - 1, [Time | Done]);
        {request, Pid} ->
            case Planned of
                0 ->
                    Pid ! done,
                    plan_loop(Planned, Waiting, Done);
                _ ->
                    Pid ! next,
                    plan_loop(Planned - 1, Waiting + 1, Done)
            end
    end.