export const TOKEN_ADDRESS: Record<number, Record<string, string>> = {
    1: {
        DAI: "0x6b175474e89094c44da98b954eedeac495271d0f",
        USDC: "0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48",
        USDT: "0xdac17f958d2ee523a2206206994597c13d831ec7"
    },
    5: {
        DAI: "0x11fE4B6AE13d2a6055C8D9cF65c55bac32B5d844",
        USDC: "0x07865c6E87B9F70255377e024ace6630C1Eaa37F"
    },
    56: {
        USDC: "0x8ac76a51cc950d9822d68b83fe1ad97b32cd580d",
        USDT: "0x55d398326f99059ff775485246999027b3197955"
    },
    137: {
        DAI: "0x8f3cf7ad23cd3cadbd9735aff958023239c6a063",
        USDC: "0x2791bca1f2de4661ed88a30c99a7a9449aa84174",
        USDT: "0xc2132d05d31c914a87c6611c10748aeb04b58e8f"
    },
    42161: {
        DAI: "0xda10009cbd5d07dd0cecc66161fc93d7c9000da1",
        USDC: "0xff970a61a04b1ca14834a43f5de4533ebddb5cc8",
        USDT: "0xfd086bc7cd5c481dcc9c85ebe478a1c0b69fcbb9"
    },
    43114: {
        DAI: "0xd586e7f844cea2f87f50152665bcbc2c279d8d70",
        USDC: "0xA7D7079b0FEaD91F3e65f86E8915Cb59c1a4C664",
        USDT: "0xc7198437980c041c805a1edcba50c1ce5db95118"
    },
    80001: {
        USDC: "0x0FA8781a83E46826621b3BC094Ea2A0212e71B23",
        USDT: "0xA02f6adc7926efeBBd59Fd43A84f4E0c0c91e832"
    },
    84531: {
        USDC: "0x1B85deDe8178E18CdE599B4C9d913534553C3dBf"
    }
}

export const NATIVE_ASSET: Record<number, string> = {
    1: "ETH",
    5: "ETH",
    56: "BNB",
    137: "MATIC",
    42161: "ETH",
    43114: "AVAX",
    80001: "MATIC",
    84531: "ETH"
}

export const ORACLE_ADDRESS: Record<number, Record<string, string>> = {
    1: {
        ETH: "0x5f4ec3df9cbd43714fe2740f5e3616155c5b8419",
        DAI: "0xaed0c38402a5d19df6e4c03f4e2dced6e29c1ee9",
        USDC: "0x8fffffd4afb6115b954bd326cbe7b4ba576818f6",
        USDT: "0x3e7d1eab13ad0104d2750b8863b489d65364e32d"
    },
    5: {
        ETH: "0xD4a33860578De61DBAbDc8BFdb98FD742fA7028e",
        DAI: "0x0d79df66BE487753B02D015Fb622DED7f0E9798d",
        USDC: "0xAb5c49580294Aff77670F839ea425f5b78ab3Ae7"
    },
    56: {
        BNB: "0x0567f2323251f0aab15c8dfb1967e4e8a7d42aee",
        USDC: "0x51597f405303c4377e36123cbc172b13269ea163",
        USDT: "0xb97ad0e74fa7d920791e90258a6e2085088b4320"
    },
    137: {
        MATIC: "0xab594600376ec9fd91f8e885dadf0ce036862de0",
        DAI: "0x4746dec9e833a82ec7c2c1356372ccf2cfcd2f3d",
        USDC: "0xfe4a8cc5b5b2366c1b58bea3858e81843581b2f7",
        USDT: "0x0a6513e40db6eb1b165753ad52e80663aea50545"
    },
    42161: {
        ETH: "0x639fe6ab55c921f74e7fac1ee960c0b6293ba612",
        DAI: "0xc5c8e77b397e531b8ec06bfb0048328b30e9ecfb",
        USDC: "0x50834f3163758fcc1df9973b6e91f0f0f0434ad3",
        USDT: "0x3f3f5df88dc9f13eac63df89ec16ef6e7e25dde7"
    },
    43114: {
        AVAX: "0x0a77230d17318075983913bc2145db16c7366156",
        DAI: "0x51d7180eda2260cc4f6e4eebb82fef5c3c2b8300",
        USDC: "0xf096872672f44d6eba71458d74fe67f9a77a23b9",
        USDT: "0xebe676ee90fe1112671f19b6b7459bc678b67e8a"
    },
    80001: {
        DAI: "0x0FCAa9c899EC5A91eBc3D5Dd869De833b06fB046",
        USDC: "0x572dDec9087154dC5dfBB1546Bb62713147e0Ab0",
        USDT: "0x92C09849638959196E976289418e5973CC96d645",
        MATIC: "0xd0D5e3DB44DE05E9F294BB0a3bEEaF030DE24Ada"
    },
    84531: {
        ETH: "0xcD2A119bD1F7DF95d706DE6F2057fDD45A0503E2",
        USDC: "0xb85765935B4d9Ab6f841c9a00690Da5F34368bc0"
    }
}
