PROJECT = rabbit_consumer_stress
PROJECT_DESCRIPTION = Rabbitmq consumer stress test
PROJECT_VERSION = 0.0.1

DEPS = amqp_client getopt

dep_amqp_client_commit = stable

ESCRIPT_EMU_ARGS += -sname stress_test

include erlang.mk
