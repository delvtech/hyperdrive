default: help

PATCH         = applyHarness.patch
CONTRACTS_DIR = ../contracts
MUNGED_DIR    = ./munged
AaveHD_origin = ../contracts/src/instances/AaveHyperdrive.sol
AaveHD_munged = ./munged/AaveHyperdrive.sol
ForwarderFactory_origin = ../contracts/src/ForwarderFactory.sol
ForwarderFactory_munged = ./munged/ForwarderFactory.sol

help:
	@echo "usage:"
	@echo "  make clean:  remove all generated files (those ignored by git)"
	@echo "  make $(MUNGED_DIR): create $(MUNGED_DIR) directory by applying the patch file to $(CONTRACTS_DIR)"
	@echo "  make record: record a new patch file capturing the differences between $(CONTRACTS_DIR) and $(MUNGED_DIR)"

munge:
	cp $(AaveHD_origin) $(MUNGED_DIR)
	cp $(ForwarderFactory_origin) $(MUNGED_DIR)
	patch -d $(MUNGED_DIR) < $(PATCH)

record:
	diff -burN $(AaveHD_origin) $(AaveHD_munged) | sed 's+\$(AaveHD_origin)/++g' | sed 's+$(AaveHD_munged)++g' > $(PATCH)
	diff -burN $(ForwarderFactory_origin) $(ForwarderFactory_munged) | sed 's+\$(ForwarderFactory_origin)/++g' | sed 's+$(ForwarderFactory_munged)++g' >> $(PATCH)

clean:
	git clean -fdX
	touch $(PATCH)