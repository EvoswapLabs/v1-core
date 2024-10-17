#[test_only]
module alice::alice_coins {
    use std::string;
    use evo_framework::deployer;
    use aptos_std::math64::pow;
    use supra_framework::managed_coin;

    struct COIN_1 has key {}

    public fun init_module(alice: &signer) {
        deployer::generate_coin<COIN_1>(
            alice,
            string::utf8(b"Test COIN_1 Coin"),
            string::utf8(b"COIN_1"),
            8,
            18446744073709551615,
            true
        );
    }
}

#[test_only]
module bob::bob_coins {
    use std::string;
    use evo_framework::deployer;
    use aptos_std::math64::pow;
    use supra_framework::coin;

    struct COIN_2 has key {}

    public fun init_module(bob: &signer) {
        deployer::generate_coin<COIN_2>(
            bob,
            string::utf8(b"Test COIN_2 Coin"),
            string::utf8(b"COIN_2"),
            9,
            1000 * pow(10, 8),
            true
        );
    }
}