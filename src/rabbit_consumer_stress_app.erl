-module(rabbit_consumer_stress_app).
-behaviour(application).

-export([start/2]).
-export([stop/1]).

start(_Type, _Args) ->
	rabbit_consumer_stress_sup:start_link().

stop(_State) ->
	ok.
