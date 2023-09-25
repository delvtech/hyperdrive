// import { get_max_long } from "hyperwasm";

const ZERO_ADDRESS = "0x".padEnd(42, "0");
const MAX_U256 = BigInt("0x".padEnd(66, "F")).toString();

async function main() {
  const { get_max_long } = await import("hyperwasm");

  const maxLong = get_max_long(
    JSON.stringify(randState()),
    MAX_U256,
    randScaled(0, 1000000000).toString()
  );

  console.log("max long:", maxLong.toString());
}

main();

async function randState() {
  const config = {
    base_token: ZERO_ADDRESS,
    governance: ZERO_ADDRESS,
    fee_collector: ZERO_ADDRESS,
    fees: {
      curve: "0",
      flat: "0",
      governance: "0",
    },
    initial_share_price: randScaled(0.5, 2.5).toString(),
    minimum_share_reserves: randScaled(0.1, 1).toString(),
    time_stretch: randScaled(0.005, 0.5).toString(),
    position_duration: randScaled(
      60 * 60 * 24 * 91,
      60 * 60 * 24 * 365
    ).toString(),
    checkpoint_duration: randScaled(60 * 60, 60 * 60 * 24).toString(),
    oracle_size: "0",
    update_gap: "0",
  };
  const info = {
    share_reserves: randScaled(1_000, 100_000_00).toString(),
    bond_reserves: rand(
      BigInt(config.initial_share_price),
      scaled(1_000_000_000)
    ).toString(),
    long_exposure: "0",
    share_price: randScaled(0.5, 2.5).toString(),
    longs_outstanding: randScaled(0, 100_000).toString(),
    shorts_outstanding: randScaled(0, 100_000).toString(),
    long_average_maturity_time: randScaled(0, 60 * 60 * 24 * 365).toString(),
    short_average_maturity_time: randScaled(0, 60 * 60 * 24 * 365).toString(),
    lp_total_supply: randScaled(1_000, 100_000_000).toString(),
    lp_share_price: randScaled(0.01, 5).toString(),
    withdrawal_shares_proceeds: randScaled(0, 100_000).toString(),
    withdrawal_shares_ready_to_withdraw: randScaled(
      1000,
      100_000_000
    ).toString(),
  };
  return { config, info };
}

/**
 * @param {bigint} min
 * @param {bigint} max
 * @returns {bigint}
 */
function rand(min, max) {
  const range = max - min;
  const bytesNeeded = Math.ceil(range.toString(2).length / 8);
  const randomBytes = new Uint8Array(bytesNeeded);

  let hexString = crypto
    .getRandomValues(randomBytes)
    .map((u8) => u8.toString(16).padStart(2, "0"))
    .join("");

  const randomBigInt = BigInt(`0x${hexString}`);

  // take the remainder of the randomBigInt divided by the range to ensure
  // we don't go over the max. Add 1 to the range to ensure we can hit the max
  return min + (randomBigInt % (range + 1n));
}

/**
 * @param {number} num
 * @returns {bigint}
 */
function scaled(num) {
  const [whole, part = ""] = num.toString().split(".");
  return BigInt(`${whole}${part.padEnd(18, "0")}`);
}

/**
 * @param {number} min
 * @param {number} max
 * @returns {bigint}
 */
function randScaled(min, max) {
  return rand(scaled(min), scaled(max));
}
