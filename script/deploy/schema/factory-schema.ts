/**
 * Numbers can be represented by either a single key as a raw value,
 * or by the keys 'value' and 'unit' to scale the input by the configured unit.
 */
type uint256 =
  | {
      /**
       * Value to be scaled by the unit.
       */
      value: number;

      /**
       * Unit to scale the value by.
       */
      unit: "ether" | "bips" | "gwei" | "weeks" | "days" | "hours" | "minutes";
    }
  | number;

/**
 * Addresses should start with a '0x' prefix and submitted as a string.
 */
type address = `0x${string}`;

export type FactoryDeployment = {
  rpcName: string;
  chainId: number;
  access: {
    admin: address;
    governance: address;
    defaultPausers: address[];
    feeCollector: address;
    sweepCollector: address;
  };
  checkpointDuration: {
    resolution: uint256;
    min: uint256;
    max: uint256;
  };
  positionDuration: {
    min: uint256;
    max: uint256;
  };
  fixedAPR: {
    min: uint256;
    max: uint256;
  };
  timeStretchAPR: {
    min: uint256;
    max: uint256;
  };
  fees: {
    curve: {
      min: uint256;
      max: uint256;
    };
    flat: {
      min: uint256;
      max: uint256;
    };
    governanceLP: {
      min: uint256;
      max: uint256;
    };
    governanceZombie: {
      min: uint256;
      max: uint256;
    };
  };
  tokens: {
    /** If an EzETH address is not provided, the coordinator will not be deployed. */
    ezeth?: address;
    /** If an LsETH address is not provided, the coordinator will not be deployed. */
    lseth?: address;
    /** If a RETH address is not provided, a mock contract will be deployed for conveniece. */
    reth?: address;
    /** If a StETH address is not provided, a mock contract will be deployed for conveniece. */
    steth?: address;
  };
};
