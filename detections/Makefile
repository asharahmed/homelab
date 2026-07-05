.PHONY: install lint convert sentinel all clean

install:
	pip install -r requirements.txt

lint:
	sigma check rules/

convert:
	mkdir -p build
	sigma convert -t splunk -p sysmon rules/windows/ -o build/windows-splunk.spl
	-sigma convert -t kusto -p microsoft_xdr rules/windows/ -o build/windows-sentinel.kql

# Regenerate the Sentinel analytics-rule parameter file from the Sigma library.
sentinel:
	cd sentinel && python generate-rules.py

all: lint convert

clean:
	rm -rf build/
