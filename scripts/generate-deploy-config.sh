#!/bin/bash

set -e

config_dir=tasks/deploy/config

# Store names of generated configurations for integration instructions at end of script.
factories=()
coordinators=()
instances=()

# Non-destructively updates the `index.ts` file for the network and global config.
function update_indexes() {
	local network=$1
	echo " - updating $config_dir/$network/index.ts"
	echo "" >"$config_dir/$network/index.ts"
	for file in "$config_dir/$network"/*; do
		base=$(basename $file)
		if [[ "$base" != 'index.ts' ]]; then
			echo "export * from \"./$(echo $base | cut -d"." -f1)\";" >>"$config_dir/$network/index.ts"
		fi
	done
	network_export="$(grep -i "$network" <"$config_dir/index.ts" || true)"
	if [[ -z $network_export ]]; then
		echo " - updating $config_dir/index.ts"
		echo "export * from \"./$network\";" >>"$config_dir/index.ts"
	fi
}

# Generates factory from `factory.env` if present, see `echo` statements for context.
factory_input=factory.env
factory_template=$config_dir/factory.ts.tmpl
factory_output_filename=factory.ts
if [ -f $factory_input ]; then
	echo "generating factory configuration..."
	echo " - reading configuration from ${factory_input}"
	export $(grep -v '^#' $factory_input | xargs)

	# Skip generation if output file already exists.
	factory_output_dir="$config_dir/$NETWORK_NAME"
	factory_output_file="$factory_output_dir/$factory_output_filename"
	if [ -f $factory_output_file ]; then
		echo " - skipping generation, factory exists for network $NETWORK_NAME"
	else
		echo " - writing configuration to ${factory_output_file}"
		mkdir -p $factory_output_dir
		envsubst <$factory_template >$factory_output_file
		update_indexes $NETWORK_NAME
		factories+="${NETWORK_NAME}_FACTORY"
	fi
	echo "done! \n"
fi

# Generates coordinator from `coordinator.env` if present, see `echo` statements for context.
coordinator_input=coordinator.env
coordinator_template=$config_dir/coordinator.ts.tmpl
if [ -f $coordinator_input ]; then
	echo "generating coordinator configuration..."
	echo " - reading configuration from ${coordinator_input}"
	export $(grep -v '^#' $coordinator_input | xargs)

	# Skip generation if output file already exists.
	coordinator_output_filename="$NAME.ts"
	coordinator_output_dir="$config_dir/$NETWORK_NAME"
	coordinator_output_file="$coordinator_output_dir/$coordinator_output_filename"
	if [ -f $coordinator_output_file ]; then
		echo " - skipping generation, coordinator exists for network $NETWORK_NAME"
	else
		echo " - writing configuration to ${coordinator_output_file}"
		mkdir -p $coordinator_output_dir
		envsubst <$coordinator_template >$coordinator_output_file
		update_indexes $NETWORK_NAME
		coordinators+="$NAME"
	fi
	echo "done! \n"
fi

# Generates instance from `instance.env` if present, see `echo` statements for context.
instance_input=instance.env
instance_template=$config_dir/instance.ts.tmpl
if [ -f $instance_input ]; then
	echo "generating instance configuration..."
	echo " - reading configuration from ${instance_input}"
	export $(grep -v '^#' $instance_input | xargs)

	# Skip generation if output file already exists.
	instance_output_filename="$NAME.ts"
	instance_output_dir="$config_dir/$NETWORK_NAME"
	instance_output_file="$instance_output_dir/$instance_output_filename"
	if [ -f $instance_output_file ]; then
		echo " - skipping generation, instance exists for network $NETWORK_NAME"
	else
		echo " - writing configuration to ${instance_output_file}"
		mkdir -p $instance_output_dir
		envsubst <$instance_template >$instance_output_file
		update_indexes $NETWORK_NAME
		instances+="$NAME"
	fi
	echo "done! \n"
fi

# Outputs instructions for integrating the generated configurations with
# existing deploy configurations in `hardhat.config.ts`.
names=(${factories[@]} ${coordinators[@]} ${instances[@]})
IFS=,\n
if [ ! ${#names[@]} -eq 0 ]; then
	echo "
    All configurations have been generated.

    Add: 

        ${names[*]}

    to the import from \"./tasks/deploy/config/\" in hardhat.config.ts

    Then, merge the following into the network configuration for \"${NETWORK_NAME}\".
  "
	if [ ! ${#factories[@]} -eq 0 ]; then
		echo "
    factories: [
          ${factories[*]}
    ]
      "
	fi
	if [ ! ${#coordinators[@]} -eq 0 ]; then
		echo "
    coordinators: [
          ${coordinators[*]}
    ]
      "
	fi
	if [ ! ${#instances[@]} -eq 0 ]; then
		echo "
    instances: [
          ${instances[*]}
    ]
      "
	fi
else
	echo "No configuration was generated."
fi
