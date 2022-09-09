.PHONY: generate ## Generates the example manifests
generate:
	./build.sh $<

.PHONY: test-e2e ## Runs the end-to-end tests
test-e2e:
	./test.sh

