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

type pool = {
  /**
   * Name of the pool
   */
  name: string;
  /**
   * Type of pool that is being deployed.
   */
  poolType: "ERC4626" | "EzETH" | "LsETH" | "RETH" | "StETH";
  /**
   * ID for the deployment as a hex string.
   */
  deploymentId: `0x${string}`;
  /**
   * Salt for the deployment as a hex string.
   */
  salt: `0x${string}`;
  /**
   * Initial contribution to the pool.
   */
  contribution: uint256;
  /**
   * Usually set to 0 since this will be configured by the deployer.
   */
  timeStretch: uint256;
  /**
   * Initial fixed rate for the pool.
   */
  fixedAPR: uint256;
  timeStretchAPR: uint256;
  /**
   * Tokens used in the vault.
   */
  tokens: {
    base: `0x${string}`;
    shares: `0x${string}`;
  };
  shareReserves: {
    min: uint256;
  };
  transactionAmounts: {
    min: uint256;
  };
  durations: {
    position: uint256;
    checkpoint: uint256;
  };
  fees: {
    curve: uint256;
    flat: uint256;
    governanceLP: uint256;
    governanceZombie: uint256;
  };
  options: {
    destination: `0x${string}`;
    asBase: boolean;
    extraData: `0x${string}`;
  };
};

export type NetworkDeployment = {
  name: string;
  profile: string;
  chainId: number;
  hyperdriveGovernance: `0x${string}`;
  admin: `0x${string}`;
  defaultPausers: `0x${string}`[];
  feeCollector: `0x${string}`;
  sweepCollector: `0x${string}`;
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
  pools: pool[];
};
