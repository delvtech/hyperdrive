import { defineCommand, runMain } from "citty";
import hre from "hardhat";

const main = defineCommand({
    meta: {
        name: "hello",
        version: "1.0.0",
        description: "My Awesome CLI App",
    },
    args: {
        name: {
            type: "positional",
            description: "Your name",
            required: true,
        },
        friendly: {
            type: "boolean",
            description: "Use friendly greeting",
        },
    },
    run({ args }) {
        console.log(`${args.friendly ? "Hi" : "Greetings"} ${args.name}!`);
        console.log(hre.network.name);
    },
});

runMain(main);
