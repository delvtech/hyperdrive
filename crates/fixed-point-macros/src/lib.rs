// TODO: These macros can be improved in two important ways:
//
// 1. Support non-decimal number formats. It would be convenient to support
//    hexadecimal and binary numbers since Rust has similar problems with those
//    number types.
// 2. Support expressions. Ideally, we would execute any expressions at compile
//    time, so we could instantiate a fixed point number to represent
//    60 * 60 * 24 seconds (for example).

use ethers::types::{I256, U256};
use proc_macro::TokenStream;
use quote::quote;
use syn::{
    parse::{Parse, ParseStream},
    parse_macro_input, LitFloat, LitInt, Result,
};

struct Number {
    digits: String,
}

impl Parse for Number {
    /// This parser uses the LitFloat and LitInt parsers to clean the input.
    fn parse(input: ParseStream) -> Result<Self> {
        let digits = if input.peek(LitFloat) {
            input.parse::<LitFloat>()?.base10_digits().to_string()
        } else if input.peek(LitInt) {
            input.parse::<LitInt>()?.base10_digits().to_string()
        } else {
            return Err(input.error("expected a float or an integer"));
        };
        Ok(Self { digits })
    }
}

impl Number {
    fn to_i256(&self) -> I256 {
        // Parse the cleaned input into a mantissa and an exponent. The U256
        // arithemetic will overflow if the mantissa or the exponent are too large.
        let mut sign = I256::one();
        let mut found_dot = false;
        let mut found_e = false;
        let mut mantissa = I256::zero();
        let mut exponent = 0;
        let mut decimals = 0;
        for digit in self.digits.chars() {
            if digit.is_digit(10) {
                let d = digit.to_digit(10).unwrap();
                if !found_e {
                    mantissa = mantissa * 10 + d;
                } else {
                    exponent = exponent * 10 + d;
                }
                if found_dot && !found_e {
                    decimals += 1;
                }
            } else if digit == '-' {
                sign = -I256::one();
            } else if digit == 'e' && !found_e {
                found_e = true;
            } else if digit == '.' && !found_dot {
                found_dot = true;
            } else {
                panic!("uint256!: unexpected character: {}", digit);
            }
        }

        // Combine the mantissa and the exponent into a single U256. This will
        // overflow if the exponent is too large. We also need to make sure that
        // the final result is an integer.
        if exponent < decimals {
            panic!("uint256!: exponent is too small");
        }
        sign * mantissa * I256::from(10).pow(exponent - decimals)
    }

    fn to_u256(&self) -> U256 {
        // Parse the cleaned input into a mantissa and an exponent. The U256
        // arithemetic will overflow if the mantissa or the exponent are too large.
        let mut found_dot = false;
        let mut found_e = false;
        let mut mantissa = U256::zero();
        let mut exponent = U256::zero();
        let mut decimals = 0;
        for digit in self.digits.chars() {
            if digit.is_digit(10) {
                let d = digit.to_digit(10).unwrap();
                if !found_e {
                    mantissa = mantissa * 10 + d;
                } else {
                    exponent = exponent * 10 + d;
                }
                if found_dot && !found_e {
                    decimals += 1;
                }
            } else if digit == 'e' && !found_e {
                found_e = true;
            } else if digit == '.' && !found_dot {
                found_dot = true;
            } else {
                panic!("uint256!: unexpected character: {}", digit);
            }
        }

        // Combine the mantissa and the exponent into a single U256. This will
        // overflow if the exponent is too large. We also need to make sure that
        // the final result is an integer.
        let decimals = U256::from(decimals);
        if exponent < decimals {
            panic!("uint256!: exponent is too small");
        }
        mantissa * U256::from(10).pow(exponent - U256::from(decimals))
    }
}

#[proc_macro]
pub fn int256(input: TokenStream) -> TokenStream {
    let result = parse_macro_input!(input as Number);
    let result: [u8; 32] = result.to_i256().into_raw().into();
    quote!(ethers::types::I256::from_raw(ethers::types::U256::from([ #(#result),* ]))).into()
}

#[proc_macro]
pub fn uint256(input: TokenStream) -> TokenStream {
    let result = parse_macro_input!(input as Number);
    let result: [u8; 32] = result.to_u256().into();
    quote!(ethers::types::U256::from([ #(#result),* ])).into()
}

#[proc_macro]
pub fn fixed(input: TokenStream) -> TokenStream {
    let result = parse_macro_input!(input as Number);
    let result: [u8; 32] = result.to_u256().into();
    quote!(FixedPoint::from([ #(#result),* ])).into()
}
