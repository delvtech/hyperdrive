default: help

PATCH         = applyHarness.patch
CONTRACTS_DIR = ../contracts
MUNGED_DIR    = ./munged
ERC4626_origin = ../contracts/src/instances/ERC4626Hyperdrive.sol
ERC4626_munged = ./munged/ERC4626Hyperdrive.sol
HD_origin = ../contracts/src/Hyperdrive.sol
HD_munged = ./munged/Hyperdrive.sol
HDLP_origin = ../contracts/src/HyperdriveLP.sol
HDLP_munged = ./munged/HyperdriveLP.sol
HDShort_origin = ../contracts/src/HyperdriveShort.sol
HDShort_munged = ./munged/HyperdriveShort.sol
HDLong_origin = ../contracts/src/HyperdriveLong.sol
HDLong_munged = ./munged/HyperdriveLong.sol
ForwarderFactory_origin = ../contracts/src/token/ForwarderFactory.sol
ForwarderFactory_munged = ./munged/ForwarderFactory.sol
AssetId_origin = ../contracts/src/libraries/AssetId.sol
AssetId_munged = ./munged/AssetId.sol

help:
	@echo "usage:"
	@echo "  make clean:  remove all generated files (those ignored by git)"
	@echo "  make $(MUNGED_DIR): create $(MUNGED_DIR) directory by applying the patch file to $(CONTRACTS_DIR)"
	@echo "  make record: record a new patch file capturing the differences between $(CONTRACTS_DIR) and $(MUNGED_DIR)"

munge:
	cp $(ERC4626_origin) $(MUNGED_DIR)
	cp $(HD_origin) $(MUNGED_DIR)
	cp $(HDLP_origin) $(MUNGED_DIR)
	cp $(HDShort_origin) $(MUNGED_DIR)
	cp $(HDLong_origin) $(MUNGED_DIR)
	cp $(ForwarderFactory_origin) $(MUNGED_DIR)
	cp $(AssetId_origin) $(MUNGED_DIR)
	patch -d $(MUNGED_DIR) < $(PATCH)

record:
	diff -burN $(ERC4626_origin) $(ERC4626_munged) | sed 's+\$(ERC4626_origin)/++g' | sed 's+$(ERC4626_munged)++g' > $(PATCH)
	diff -burN $(HD_origin) $(HD_munged) | sed 's+\$(HD_origin)/++g' | sed 's+$(HD_munged)++g' >> $(PATCH)
	diff -burN $(HDLP_origin) $(HDLP_munged) | sed 's+\$(HDLP_origin)/++g' | sed 's+$(HDLP_munged)++g' >> $(PATCH)
	diff -burN $(HDShort_origin) $(HDShort_munged) | sed 's+\$(HDShort_origin)/++g' | sed 's+$(HDShort_munged)++g' >> $(PATCH)
	diff -burN $(HDLong_origin) $(HDLong_munged) | sed 's+\$(HDLong_origin)/++g' | sed 's+$(HDLong_munged)++g' >> $(PATCH)
	diff -burN $(ForwarderFactory_origin) $(ForwarderFactory_munged) | sed 's+\$(ForwarderFactory_origin)/++g' | sed 's+$(ForwarderFactory_munged)++g' >> $(PATCH)
	diff -burN $(AssetId_origin) $(AssetId_munged) | sed 's+\$(AssetId_origin)/++g' | sed 's+$(AssetId_munged)++g' >> $(PATCH)

clean:
	git clean -fdX
	touch $(PATCH)