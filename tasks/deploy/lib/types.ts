import dayjs from "dayjs";
import duration, { DurationUnitType } from "dayjs/plugin/duration";
import { pad, parseEther } from "viem";
import { z } from "zod";

dayjs.extend(duration);

/**
 * Specifies a 42 character string with the prefix '0x'
 */
export const zAddress = z.custom<`0x${string}`>(
    (v) => typeof v === "string" && /^0x[\da-fA-F]{40}$/g.test(v),
);

/**
 * Specifies a string of any length with the prefix '0x'
 */
export const zHex = z.custom<`0x${string}`>(
    (v) => typeof v === "string" && /^0x[\da-fA-F]*$/g.test(v),
);

/**
 * Specifies a string with the prefix '0x' to be converted to bytes32
 */
export const zBytes32 = z
    .custom<`0x${string}`>((v) => typeof v === "string" && /^0x[\da-fA-F]*$/g.test(v))
    .transform((v) => pad(v, { size: 32 }));

/**
 * Accepted lengths of time for duration specification
 */
export const durationUnits = [
    "minute",
    "minutes",
    "hour",
    "hours",
    "day",
    "days",
    "week",
    "weeks",
    "year",
    "years",
];

export type DurationString = `${number} ${(typeof durationUnits)[number]}`;

/**
 * Accepts durations of the following form using {@link durationUnits}
 */
export const parseDuration = (d: DurationString) => {
    const parts = d.split(" ");
    if (parts.length != 2) throw new Error(`invalid duration string "${d}"`);
    const [quantityString, unit] = parts;
    if (!durationUnits.includes(unit)) throw new Error(`invalid unit ${unit}`);
    if (isNaN(parseInt(quantityString)))
        throw new Error(`invalid quantity ${quantityString}`);
    return BigInt(
        dayjs
            .duration(parseInt(quantityString), unit as DurationUnitType)
            .asSeconds(),
    );
};

/**
 * Converts the input duration to seconds and casts it as a bigint. Accepts the following formats:
 * - number: assumed to be seconds and no conversion is performed
 * - string: `${number} ${minute(s) | hour(s) | day(s) | week(s) | year(s)}`
 *
 * NOTE: months aren't included because they're unclear
 */
export const zDuration = z
    .custom<
        string | number
    >((v) => typeof v === "number" || (typeof v === "string" && !isNaN(parseInt(v))) || (typeof v === "string" && v.split(" ").length == 2 && !isNaN(parseInt(v.split(" ").at(0)!)) && durationUnits.includes(v.split(" ").at(1)!)))
    .transform((v) =>
        typeof v === "number" || (typeof v === "string" && isBigInt(v))
            ? BigInt(v)
            : BigInt(parseDuration(v)),
    );

export type Duration = z.infer<typeof zDuration>;

function isBigInt(value: string) {
    try {
        return BigInt(parseInt(value, 10)) !== BigInt(value);
    } catch (e) {
        return false;
    }
}

/**
 * Accepts numbers or strings and converts to bigint
 */
export const zEther = z
    .custom<
        string | number
    >((v) => typeof v === "number" || isBigInt(v) || !isNaN(parseFloat(v)))
    .transform((v) => parseEther(v.toString()));

export type Ether = z.infer<typeof zEther>;

/**
 * Expnads the fields for object-based types in intellisense/lsp
 */
export type Prettify<T> = {
    [K in keyof T]: T[K];
} & {};
