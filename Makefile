PROJECT = rabbit_stress
PROJECT_DESCRIPTION = Rabbitmq consumer stress test
PROJECT_VERSION = 0.0.1

DEPS = amqp_client getopt gun

dep_amqp_client_commit = stable

include erlang.mk


escript::
	cp rabbit_stress rabbit_consumer_stress
	cp rabbit_stress rabbit_http_stress
	rm rabbit_stress