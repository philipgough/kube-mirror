.PHONY: generate ## Generates the example manifests
generate:
	./build.sh $<

.PHONY: test-e2e ## Runs the end-to-end tests
test-e2e:
	./test.sh

.PHONY: fmt ## Formats the code
fmt:
	jsonnetfmt -n 2 --max-blank-lines 2 --string-style s --comment-style s -i jsonnet/kube-mirror.libsonnet
