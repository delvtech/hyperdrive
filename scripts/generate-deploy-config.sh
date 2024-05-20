#!/bin/sh

set -e

function update_index(){
  local config_dir=$1
  echo "" > "$config_dir/index.ts"
  for file in "$config_dir"/*; do
    if [[ "$file" != 'index.ts' ]]; then
      echo "export * from \"./$(basename $file | cut -d"." -f1)\";" >> "$config_dir/index.ts"
    fi
  done
}

factory_input=factory.env
factory_template=tasks/deploy/config/factory.ts.tmpl
factory_output_filename=factory.ts
if [ -f $factory_input ]; then
	echo "generating factory configuration..."
	echo " - reading configuration from ${factory_input}"
	export $(grep -v '^#' $factory_input | xargs)

	factory_output_dir="tasks/deploy/config/$NETWORK_NAME"
	factory_output_file="$factory_output_dir/$factory_output_filename"
	if [ -f $factory_output_file ]; then
		echo " - skipping generation, factory exists for network $NETWORK_NAME"
	else
		echo " - writing configuration to ${factory_output_file}"
		mkdir -p $factory_output_dir
		envsubst <$factory_template >$factory_output_file
    update_index "$factory_output_dir"
	fi 
	echo "done! \n"
fi

coordinator_input=coordinator.env
coordinator_template=tasks/deploy/config/coordinator.ts.tmpl
if [ -f $coordinator_input ]; then
	echo "generating coordinator configuration..."
	echo " - reading configuration from ${coordinator_input}"
	export $(grep -v '^#' $coordinator_input | xargs)

	coordinator_output_filename="$NAME.ts"
	coordinator_output_dir="tasks/deploy/config/$NETWORK_NAME"
	coordinator_output_file="$coordinator_output_dir/$coordinator_output_filename"
	if [ -f $coordinator_output_file ]; then
		echo " - skipping generation, coordinator exists for network $NETWORK_NAME"
	else
		echo " - writing configuration to ${coordinator_output_file}"
		mkdir -p $coordinator_output_dir
		envsubst <$coordinator_template >$coordinator_output_file
    update_index "$coordinator_output_dir"
	fi
	echo "done! \n"
fi

instance_input=instance.env
instance_template=tasks/deploy/config/instance.ts.tmpl
if [ -f $instance_input ]; then
	echo "generating instance configuration..."
	echo " - reading configuration from ${instance_input}"
	export $(grep -v '^#' $instance_input | xargs)

	instance_output_filename="$NAME.ts"
	instance_output_dir="tasks/deploy/config/$NETWORK_NAME"
	instance_output_file="$instance_output_dir/$instance_output_filename"
	if [ -f $instance_output_file ]; then
		echo " - skipping generation, instance exists for network $NETWORK_NAME"
	else
		echo " - writing configuration to ${instance_output_file}"
		mkdir -p $instance_output_dir
		envsubst <$instance_template >$instance_output_file
    update_index "$instance_output_dir"
	fi
	echo "done! \n"
fi
