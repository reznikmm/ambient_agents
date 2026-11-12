.PHONY: all build test eval run dashboard start stop format
all: build
build:
	alr -C ada build
test: build
	alr -C ada test
eval: build
	ada/bin/ambient_evals
run: build
	./ada/run.sh
dashboard: build
	./ada/run.sh --dashboard
start:
	./ada/workshop.sh start
stop:
	./ada/workshop.sh stop
format:
	alr -C ada exec -- gnatformat --charset=utf-8 --no-subprojects -P ambient_workshop.gpr
