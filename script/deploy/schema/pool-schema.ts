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
 * Bytes32 should start with a '0x' prefix and submitted as a string.
 */
type bytes32 = `0x${string}`;

/**
 * Addresses should start with a '0x' prefix and submitted as a string.
 */
type address = `0x${string}`;

export type PoolDeployment = {
  rpcName: string;
  chainId: number;
  /** Name of the pool. */
  name: string;
  /** Address of the pool's factory contract. */
  factory: address;
  /** Coordinator address for the pool that is being deployed. */
  coordinator: address;
  /** Hyperdrive registry address. */
  registry: address;
  /** ID for the deployment as a `bytes32` hex string. */
  deploymentId: bytes32;
  /** Salt for the deployment as a `bytes32` hex string. */
  salt: bytes32;
  /** Initial contribution to the pool. */
  contribution: uint256;
  /** Usually set to 0 since this will be configured by the deployer. */
  timeStretch: uint256;
  /** Initial fixed rate for the pool. */
  fixedAPR: uint256;
  timeStretchAPR: uint256;
  /** Token addresses used in the vault. */
  tokens: {
    base: address;
    shares: address;
  };
  bounds: {
    minimumShareReserves: uint256;
    minimumTransactionAmount: uint256;
    positionDuration: uint256;
    checkpointDuration: uint256;
    timestretch: uint256;
  };
  access: {
    admin: address;
    governance: address;
    feeCollector: address;
    sweepCollector: address;
  };
  fees: {
    curve: uint256;
    /** The value provided for the flat fee will be annualized (flat * (position_duration / 365_days)). */
    flat: uint256;
    governanceLP: uint256;
    governanceZombie: uint256;
  };
  options: {
    /** Recipient of shares issued from the contribution. */
    destination: address;
    asBase: boolean;
    extraData: bytes32;
  };
};
