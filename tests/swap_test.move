#[test_only]
module evo::swap_test {
    use std::signer;
    use std::string;

    use alice::alice_coins::{Self, COIN_1 };
    use bob::bob_coins::{Self, COIN_2 };

    use supra_framework::account;
    use supra_framework::supra_coin::{Self, SupraCoin as APT};
    use supra_framework::coin;
    use supra_framework::genesis;
    use supra_framework::managed_coin;

    use supra_framework::resource_account;

    use aptos_std::debug;
    use aptos_std::math64::pow;
    
    use evo::math;
    use evo::swap_utils;

    use evo_framework::deployer;

    use evo::admin;
    use evo::fee_on_transfer;
    use evo::stake;
    use evo::swap::{Self, LPToken};
    use evo::router;

    use std::features;

    const MAX_U64: u64 = 18446744073709551615;
    const MINIMUM_LIQUIDITY: u128 = 1000;

    public fun setup_test(supra_framework: signer, evo_framework: &signer, dev: &signer, admin: &signer, treasury: &signer, resource_account: &signer, alice: &signer, bob: &signer) {
        let (supra_coin_burn_cap, supra_coin_mint_cap) = supra_coin::initialize_for_test_without_aggregator_factory(&supra_framework);
        // features::change_feature_flags(&supra_framework, vector[26], vector[]);
        account::create_account_for_test(signer::address_of(dev));
        account::create_account_for_test(signer::address_of(admin));
        // account::create_account_for_test(signer::address_of(treasury));
        resource_account::create_resource_account(dev, b"evo-v1", x"");
        admin::init_test(resource_account);
        account::create_account_for_test(signer::address_of(evo_framework));
        coin::register<APT>(evo_framework);    // for the deployer
        deployer::init_test(evo_framework, 1, signer::address_of(evo_framework));

        // treasury
        // admin::offer_treasury_previliges(resource_account, signer::address_of(treasury), 123);
        // admin::claim_treasury_previliges(treasury, 123);

        account::create_account_for_test(signer::address_of(alice));
        account::create_account_for_test(signer::address_of(bob));
        managed_coin::register<APT>(alice);
        managed_coin::register<APT>(bob);
        coin::register<APT>(treasury);
        
        // mint some APT to be able to pay for the fee of generate_coin
        supra_coin::mint(&supra_framework, signer::address_of(alice), 100000000000 * pow(10, 8));
        supra_coin::mint(&supra_framework, signer::address_of(bob), 10000000000 * pow(10, 8));
        // destroy APT mint and burn caps
        coin::destroy_mint_cap<APT>(supra_coin_mint_cap);
        coin::destroy_burn_cap<APT>(supra_coin_burn_cap);

        alice_coins::init_module(alice);
        bob_coins::init_module(bob);

        coin::register<COIN_2>(alice);
        coin::register<COIN_1>(bob);
    }

    public fun setup_test_with_genesis(supra_framework: signer, evo_framework: &signer, dev: &signer, admin: &signer, treasury: &signer, resource_account: &signer, alice: &signer, bob: &signer) {
        genesis::setup();
        setup_test(supra_framework, evo_framework, dev, admin, treasury, resource_account, alice, bob);
    }

    #[test(supra_framework = @0x1, evo_framework = @evo_framework, dev = @dev, admin= @admin, treasury = @treasury, resource_account = @evo, alice = @0x123, bob = @0x456)]
    fun test_fee_on_transfer(
        supra_framework: signer,
        evo_framework: &signer,
        dev: &signer,
        admin: &signer,
        treasury: &signer,
        resource_account: &signer,
        alice: &signer,
        bob: &signer,
    ) {
        setup_test_with_genesis(supra_framework, evo_framework, dev, admin, treasury, resource_account, alice, bob);
        fee_on_transfer::initialize_fee_on_transfer_for_test<COIN_1>(alice, 100, 100, 100);
        // create pair
        router::create_pair<COIN_1, APT>(bob);
        let alice_liquidity_x = 10 * pow(10, 8);
        let alice_liquidity_y = 10 * pow(10, 8);
        // alice provider liquidity for COIN_1-APT
        router::add_liquidity<APT, COIN_1>(alice, 2000000000000000, 2000000000000000, 0, 0);
        // 2726116900000000
        // 10000000000
        // initialize fee on transfer of both tokens
        let fee_on_transfer = fee_on_transfer::get_all_fee_on_transfer<COIN_1>();
        debug::print<u128>(&fee_on_transfer);
        coin::register<COIN_1>(treasury);
        router::swap_exact_input<APT, COIN_1>(
            alice, 
            2726116900000000, 
            11108791839271
        );

        // register fee on transfer in the pairs
        // router::register_fee_on_transfer_in_a_pair<COIN_1, COIN_1, APT>(alice);
        // assert!(swap::is_fee_on_transfer_registered<COIN_1, COIN_1, APT>(), 1);
        assert!(swap::is_fee_on_transfer_registered<COIN_1, APT, COIN_1>(), 0);
        assert!(!swap::is_fee_on_transfer_registered<APT, APT, COIN_1>(), 0);
        // set new liquidity fee on transfer
        fee_on_transfer::set_liquidity_fee<COIN_1>(alice, 200);
        // set new fees
        fee_on_transfer::set_all_fees<COIN_1>(alice, 500, 500, 500);
        assert!(fee_on_transfer::get_all_fee_on_transfer<COIN_1>() == 1500, 1);
        assert!(fee_on_transfer::get_liquidity_fee<COIN_1>() == 500, 2);
        assert!(fee_on_transfer::get_rewards_fee<COIN_1>() == 500, 3);
        assert!(fee_on_transfer::get_team_fee<COIN_1>() == 500, 4);
    }

    #[test(supra_framework = @0x1, evo_framework = @evo_framework, dev = @dev, admin= @admin, resource_account = @evo, treasury = @treasury, alice = @0x123, bob = @0x456)]
    fun test_swap_exact_input(
        supra_framework: signer,
        evo_framework: &signer, 
        dev: &signer,
        admin: &signer,
        resource_account: &signer,
        treasury: &signer,
        bob: &signer,
        alice: &signer,
    ) {
        setup_test_with_genesis(supra_framework, evo_framework, dev, admin, treasury, resource_account, alice, bob);

        coin::transfer<COIN_1>(alice, signer::address_of(bob), 10 * pow(10, 8));
        coin::transfer<COIN_2>(bob, signer::address_of(alice), 10 * pow(10, 8));

        coin::register<COIN_2>(alice);
        coin::register<COIN_1>(bob);
        coin::register<COIN_1>(treasury);
        coin::register<COIN_2>(treasury);

        // create pair
        router::create_pair<COIN_1, COIN_2>(alice);
        // these are needed for transferring some of the fees since we want them in APT
        router::create_pair<COIN_1, APT>(alice);
        router::create_pair<COIN_2, APT>(alice);

        let bob_liquidity_x = 10 * pow(10, 8);
        let bob_liquidity_y = 10 * pow(10, 8);
        let alice_liquidity_x = 2 * pow(10, 8);
        let alice_liquidity_y = 4 * pow(10, 8);

        // bob provider liquidity for COIN_1-COIN_2
        router::add_liquidity<COIN_1, COIN_2>(bob, bob_liquidity_x, bob_liquidity_y, 0, 0);
        // for the other pairs as well
        router::add_liquidity<COIN_1, APT>(alice, alice_liquidity_x, alice_liquidity_y, 0, 0);
        router::add_liquidity<COIN_2, APT>(bob, alice_liquidity_x, alice_liquidity_y, 0, 0);

        // TODO: assert liquidity pools equal to inputted ones
        let input_x = 2 * pow(10, 6);
        router::swap_exact_input<COIN_1, COIN_2>(alice, input_x, 0);
        // debug::print<address>(&swap::fee_to());
    }

    #[test(supra_framework = @0x1, evo_framework = @evo_framework, dev = @dev, admin= @admin, resource_account = @evo, treasury = @treasury, alice = @0x123, bob = @0x456)]
    fun test_swap_exact_output(
        supra_framework: signer,
        evo_framework: &signer, 
        dev: &signer,
        admin: &signer,
        resource_account: &signer,
        treasury: &signer,
        bob: &signer,
        alice: &signer,
    ) {
        setup_test_with_genesis(supra_framework, evo_framework, dev, admin, treasury, resource_account, alice, bob);

        coin::transfer<COIN_1>(alice, signer::address_of(bob), 10 * pow(10, 8));
        coin::transfer<COIN_2>(bob, signer::address_of(alice), 10 * pow(10, 8));

        coin::register<COIN_2>(alice);
        coin::register<COIN_1>(bob);
        // coin::register<COIN_1>(treasury);
        // coin::register<COIN_2>(treasury);

        // create pair
        router::create_pair<COIN_1, COIN_2>(alice);
        // these are needed for transferring some of the fees since we want them in APT
        router::create_pair<COIN_1, APT>(alice);
        router::create_pair<COIN_2, APT>(alice);

        let bob_liquidity_x = 10 * pow(10, 8);
        let bob_liquidity_y = 10 * pow(10, 8);
        let alice_liquidity_x = 2 * pow(10, 8);
        let alice_liquidity_y = 4 * pow(10, 8);

        // bob provider liquidity for COIN_1-COIN_2
        router::add_liquidity<COIN_1, COIN_2>(bob, bob_liquidity_x, bob_liquidity_y, 0, 0);
        // for the other pairs as well
        router::add_liquidity<COIN_1, APT>(alice, alice_liquidity_x, alice_liquidity_y, 0, 0);
        router::add_liquidity<COIN_2, APT>(bob, alice_liquidity_x, alice_liquidity_y, 0, 0);
        
        router::swap_exact_output<COIN_1, COIN_2>(
            alice, 
            2 * pow(10, 6), 
            MAX_U64
        );
    }

    #[test(supra_framework = @0x1, evo_framework = @evo_framework, dev = @dev, admin= @admin, treasury = @treasury, resource_account = @evo, alice = @0x123, bob = @0x456)]
    fun test_liquidity_addition_and_removal(
        supra_framework: signer,
        evo_framework: &signer,
        dev: &signer,
        admin: &signer,
        treasury: &signer,
        resource_account: &signer,
        alice: &signer,
        bob: &signer,
    ) {
        setup_test_with_genesis(supra_framework, evo_framework, dev, admin, treasury, resource_account, alice, bob);

        coin::transfer<COIN_1>(alice, signer::address_of(bob), 10 * pow(10, 8));
        coin::transfer<COIN_2>(bob, signer::address_of(alice), 10 * pow(10, 8));

        // create pair
        router::create_pair<COIN_1, COIN_2>(alice);

        let bob_liquidity_x = 10 * pow(10, 8);
        let bob_liquidity_y = 10 * pow(10, 8);
        let alice_liquidity_x = 2 * pow(10, 8);
        let alice_liquidity_y = 4 * pow(10, 8);

        // provide liquidity 
        router::add_liquidity<COIN_1, COIN_2>(bob, bob_liquidity_x, bob_liquidity_y, 0, 0);
        let (x_reserve, y_reserve, _) = swap::token_reserves<COIN_1, COIN_2>();
        assert!(x_reserve == bob_liquidity_x, 1);
        assert!(y_reserve == bob_liquidity_y, 2);
        debug::print<u128>(&(swap::total_lp_supply<COIN_1, COIN_2>()));
        
        router::add_liquidity<COIN_1, COIN_2>(alice, alice_liquidity_x, alice_liquidity_y, 0, 0);
        let (x_reserve, y_reserve, _) = swap::token_reserves<COIN_1, COIN_2>();
        
        debug::print<u64>(&(bob_liquidity_y + alice_liquidity_y));
        debug::print<u64>(&y_reserve);

        // remove liquidity
        router::remove_liquidity<COIN_1, COIN_2>(bob, 1 * pow(10, 6), 0, 0);
        let (x_reserve, y_reserve, _) = swap::token_reserves<COIN_1, COIN_2>();
        assert!(x_reserve == bob_liquidity_x + alice_liquidity_x - 1 * pow(10, 6), 5);
        
        debug::print<u64>(&(bob_liquidity_y + alice_liquidity_y));
        debug::print<u64>(&y_reserve);

        router::remove_liquidity<COIN_1, COIN_2>(alice, 1 * pow(10, 6), 0, 0);
        let (x_reserve, y_reserve, _) = swap::token_reserves<COIN_1, COIN_2>();
        
        debug::print<u64>(&(bob_liquidity_y + alice_liquidity_y));
        debug::print<u64>(&y_reserve);
    }

    #[test(supra_framework = @0x1, evo_framework = @evo_framework, dev = @dev, admin= @admin, resource_account = @evo, treasury = @treasury, alice = @0x123, bob = @0x456)]
    fun test_stake_with_only_one_fee_transfer(
        supra_framework: signer,
        evo_framework: &signer, 
        dev: &signer,
        admin: &signer,
        resource_account: &signer,
        treasury: &signer,
        bob: &signer,
        alice: &signer,
    ) {
        setup_test_with_genesis(supra_framework, evo_framework, dev, admin, treasury, resource_account, alice, bob);
        coin::register<COIN_1>(treasury);

        // create pair
        router::create_pair<COIN_1, APT>(alice);

        let alice_liquidity_x = 10 * pow(10, 8);
        let alice_liquidity_y = 10 * pow(10, 8);

        // alice provider liquidity for COIN_1-APT
        router::add_liquidity<APT, COIN_1>(alice, alice_liquidity_x, alice_liquidity_y, 0, 0);

        // initialize fee on transfer of both tokens
        fee_on_transfer::initialize_fee_on_transfer_for_test<COIN_1>(alice, 100, 100, 100);
        let fee_on_transfer = fee_on_transfer::get_all_fee_on_transfer<COIN_1>();
        debug::print<u128>(&fee_on_transfer);
        coin::register<COIN_1>(treasury);

        // register fee on transfer in the pairs
        router::register_fee_on_transfer_in_a_pair<COIN_1, COIN_1, APT>(alice);
        // assert!(swap::is_fee_on_transfer_registered<COIN_1, COIN_1, APT>(), 1);
        assert!(swap::is_fee_on_transfer_registered<COIN_1, APT, COIN_1>(), 0);
        assert!(!swap::is_fee_on_transfer_registered<APT, APT, COIN_1>(), 0);

        // stake
        router::stake_tokens_in_pool<COIN_1, APT>(alice, 5 * pow(10, 8));

        coin::transfer<COIN_1>(alice, signer::address_of(bob), 5 * pow(10, 8));

        debug::print<u64>(&coin::balance<APT>(signer::address_of(alice)));
        debug::print<u64>(&coin::balance<COIN_1>(signer::address_of(alice)));
        // swap
        let input_x = 2 * pow(10, 6);
        router::swap_exact_input<APT, COIN_1>(bob, input_x, 0);
        // router::swap_exact_output<APT, COIN_1>(alice, 2 * pow(10, 5), MAX_U64);
        router::swap_exact_input<COIN_1, APT>(bob, input_x, 0);
        // router::swap_exact_output<COIN_1, APT>(alice, 2 * pow(10, 5), MAX_U64);
        
        debug::print<u64>(&coin::balance<APT>(signer::address_of(alice)));
        debug::print<u64>(&coin::balance<COIN_1>(signer::address_of(alice)));

        // Based on sorting of the pairs, the pair is COIN_1-APT
        assert!(swap::is_pair_created<COIN_1, APT>(), 1);
        
        let (pool_balance_x_before_adding_rewards, pool_balance_y_before_adding_rewards) = stake::get_rewards_fees_accumulated<COIN_1, APT>();
        
        debug::print<u64>(&pool_balance_x_before_adding_rewards);
        debug::print<u64>(&pool_balance_y_before_adding_rewards);

        // add rewards
        router::add_rewards_to_pool<COIN_1, APT, COIN_1>(alice, 1 * pow(10, 8));
        router::add_rewards_to_pool<COIN_1, APT, APT>(alice, 1 * pow(10, 8));
        
        let (pool_balance_x_after_adding_rewards, pool_balance_y_after_adding_rewards) = stake::get_rewards_fees_accumulated<COIN_1, APT>();

        debug::print<u64>(&pool_balance_x_after_adding_rewards);
        debug::print<u64>(&pool_balance_y_after_adding_rewards);

        // swap again
        router::swap_exact_input<APT, COIN_1>(bob, input_x, 0);
        router::swap_exact_input<COIN_1, APT>(bob, input_x, 0);

        // claim rewards
        router::claim_rewards_from_pool<COIN_1, APT>(alice);

        let (pool_balance_x_after_claiming_rewards, pool_balance_y_after_claiming_rewards) = stake::get_rewards_fees_accumulated<COIN_1, APT>();

        debug::print<u64>(&pool_balance_x_after_claiming_rewards);
        debug::print<u64>(&pool_balance_y_after_claiming_rewards);

        // unstake 
        router::unstake_tokens_from_pool<COIN_1, APT>(alice, 5 * pow(10, 8));

        // treasury wallet receives the treasury fee
        // debug::print<u64>(&coin::balance<COIN_1>(@treasury));

        // router::claim_accumulated_team_fee<COIN_1, COIN_1, APT>(alice);
        // assert!(alice_balance_x == 0 && alice_balance_y == 0, 125);
        // debug::print_stack_trace();

        // // get rewards pool info
        // let (staked_tokens, balance_x, balance_y, magnified_dividends_per_share_x, magnified_dividends_per_share_y, precision_factor, is_x_staked) = stake::token_rewards_pool_info<COIN_1, APT>();
        // debug::print<u64>(&staked_tokens);
        // debug::print<u64>(&balance_x);
        // debug::print<u64>(&balance_y);
        // debug::print<u128>(&magnified_dividends_per_share_x);
        // debug::print<u128>(&magnified_dividends_per_share_y);

        // //// bob stake tokens
        // // coin::transfer<COIN_1>(alice, signer::address_of(bob), 5 * pow(10, 8));
        // // router::stake_tokens_in_pool<COIN_1, APT>(bob, 5 * pow(10, 8));
        // // unstake 
        // router::unstake_tokens_from_pool<COIN_1, APT>(alice, 1 * pow(10, 8));
        // router::unstake_tokens_from_pool<COIN_1, APT>(alice, 1 * pow(10, 8));
        // router::unstake_tokens_from_pool<COIN_1, APT>(alice, 1 * pow(10, 8));
        // router::unstake_tokens_from_pool<COIN_1, APT>(alice, 1 * pow(10, 8));
        // router::unstake_tokens_from_pool<COIN_1, APT>(alice, 5 * pow(10, 7));
        // router::unstake_tokens_from_pool<COIN_1, APT>(alice, 1 * pow(10, 7));
        // router::unstake_tokens_from_pool<COIN_1, APT>(alice, 1 * pow(10, 7));
        // router::unstake_tokens_from_pool<COIN_1, APT>(alice, 1 * pow(10, 7));
        
        // // router::unstake_tokens_from_pool<COIN_1, APT>(alice, 1 * pow(10, 8));
        // let (staked_tokens, balance_x, balance_y, magnified_dividends_per_share_x, magnified_dividends_per_share_y, precision_factor, is_x_staked) = stake::token_rewards_pool_info<COIN_1, APT>();
        // debug::print<u64>(&staked_tokens);
        // debug::print<u64>(&balance_x);
        // debug::print<u64>(&balance_y);
        // debug::print<u128>(&magnified_dividends_per_share_x);
        // debug::print<u128>(&magnified_dividends_per_share_y);
    }   

    #[test(supra_framework = @0x1, evo_framework = @evo_framework, dev = @dev, admin= @admin, resource_account = @evo, treasury = @treasury, alice = @0x123, bob = @0x456)]
    fun test_create_and_stake_tokens(
        supra_framework: signer,
        evo_framework: &signer, 
        dev: &signer,
        admin: &signer,
        resource_account: &signer,
        treasury: &signer,
        bob: &signer,
        alice: &signer,
    ) {
        setup_test_with_genesis(supra_framework, evo_framework, dev, admin, treasury, resource_account, alice, bob);
        coin::register<COIN_1>(treasury);
        coin::register<COIN_2>(treasury);
        coin::transfer<COIN_1>(alice, signer::address_of(bob), 10 * pow(10, 8));
        coin::transfer<COIN_2>(bob, signer::address_of(alice), 10 * pow(10, 8));

        // create pair
        router::create_pair<COIN_1, COIN_2>(alice);
        router::create_pair<COIN_1, APT>(alice);
        router::create_pair<COIN_2, APT>(alice);

        let bob_liquidity_x = 10 * pow(10, 8);
        let bob_liquidity_y = 10 * pow(10, 8);
        let alice_liquidity_x = 15 * pow(10, 8);
        let alice_liquidity_y = 15 * pow(10, 8);

        // bob provider liquidity for COIN_1-COIN_2
        router::add_liquidity<COIN_1, COIN_2>(bob, bob_liquidity_x, bob_liquidity_y, 0, 0);

        // initialize fee on transfer of both tokens
        fee_on_transfer::initialize_fee_on_transfer_for_test<COIN_1>(alice, 10, 20, 30);
        fee_on_transfer::initialize_fee_on_transfer_for_test<COIN_2>(bob, 35, 55, 15);

        // register fee on transfer in the pairs
        router::register_fee_on_transfer_in_a_pair<COIN_1, COIN_1, COIN_2>(alice);
        router::register_fee_on_transfer_in_a_pair<COIN_2, COIN_1, COIN_2>(bob);

        // rewards pool
        let response = stake::is_pool_created<COIN_1, COIN_2>();
        debug::print<bool>(&response); 

        debug::print<u64>(&coin::balance<COIN_1>(signer::address_of(alice)));
        debug::print<u64>(&coin::balance<COIN_2>(signer::address_of(bob)));

        router::stake_tokens_in_pool<COIN_2, COIN_1>(alice, 5 * pow(10, 8));
        router::stake_tokens_in_pool<COIN_1, COIN_2>(alice, 5 * pow(10, 8));

        debug::print<u64>(&coin::balance<COIN_1>(signer::address_of(alice)));
        debug::print<u64>(&coin::balance<COIN_2>(signer::address_of(bob)));

        let (staked_tokens, balance_x, balance_y, magnified_dividends_per_share_x, magnified_dividends_per_share_y, precision_factor, is_x_staked) = stake::token_rewards_pool_info<COIN_1, COIN_2>();

        assert!(staked_tokens == 5 * pow(10, 8), 130);

        let (pool_balance_x, pool_balance_y) = stake::get_rewards_fees_accumulated<COIN_1, COIN_2>();

        assert!(pool_balance_x == 0, 126);
        assert!(pool_balance_y == 0, 126);

        let (pool_balance_x, pool_balance_y) = stake::get_rewards_fees_accumulated<COIN_1, COIN_2>();

        debug::print<u64>(&pool_balance_x);
        debug::print<u64>(&pool_balance_y);

        // swap
        let input_x = 2 * pow(10, 6);

        let (reserve_x, reserve_y, _) = swap::token_reserves<COIN_1, COIN_2>();
        let liquidity = (swap::total_lp_supply<COIN_1, COIN_2>() as u64);

        debug::print<u64>(&liquidity);
        debug::print<u64>(&reserve_x);
        debug::print<u64>(&reserve_y);

        router::swap_exact_input<COIN_1, COIN_2>(alice, input_x, 0);
        debug::print<u64>(&coin::balance<COIN_2>(@treasury));
        debug::print<u64>(&coin::balance<COIN_1>(@treasury));
        // assert!(coin::balance<COIN_2>(@treasury) = 2 * pow(10, 6), 111);
        router::swap_exact_input<COIN_2, COIN_1>(bob, input_x, 0);
        router::swap_exact_input<COIN_1, COIN_2>(alice, input_x, 0);
        // router::swap_exact_output<COIN_1, COIN_2>(alice, 1 * pow(10, 4), MAX_U64);
        let (staked_tokens, balance_x, balance_y, magnified_dividends_per_share_x, magnified_dividends_per_share_y, precision_factor, is_x_staked) = stake::token_rewards_pool_info<COIN_1, COIN_2>();
        let liquidity = (swap::total_lp_supply<COIN_1, COIN_2>() as u64);
        
        debug::print<u64>(&liquidity);
        debug::print<u64>(&reserve_x);
        debug::print<u64>(&reserve_y);

        let (pool_balance_x, pool_balance_y) = stake::get_rewards_fees_accumulated<COIN_1, COIN_2>();

        debug::print<u64>(&pool_balance_x);
        debug::print<u64>(&pool_balance_y);

        let (second_pool_balance_x, second_pool_balance_y) = stake::get_rewards_fees_accumulated<COIN_2, COIN_1>();

        debug::print<u64>(&second_pool_balance_x);
        debug::print<u64>(&second_pool_balance_y);

        // treasury receives the swap fee
        debug::print<u64>(&coin::balance<COIN_1>(@treasury));
        debug::print<u64>(&coin::balance<COIN_2>(@treasury));

        // add liquidity
        router::add_liquidity<COIN_1, APT>(alice, 2 * pow(10, 8), 2 * pow(10, 8), 0, 0);
        // register fee on transfer in the pair COIN_1-APT
        router::register_fee_on_transfer_in_a_pair<COIN_1, COIN_1, APT>(alice);
        // set new fee on transfer fees
        fee_on_transfer::set_liquidity_fee<COIN_1>(alice, 500);
        fee_on_transfer::set_rewards_fee<COIN_1>(alice, 500);
        fee_on_transfer::set_team_fee<COIN_1>(alice, 500);
    }

    #[test(supra_framework = @0x1, evo_framework = @evo_framework, dev = @dev, admin= @admin, resource_account = @evo, treasury = @treasury, alice = @0x123, bob = @0x456)]
    // execute multiple swaps and assert treasury balance
    fun test_treasury_balance(
        supra_framework: signer,
        evo_framework: &signer, 
        dev: &signer,
        admin: &signer,
        resource_account: &signer,
        treasury: &signer,
        bob: &signer,
        alice: &signer,
    ) {
        setup_test_with_genesis(supra_framework, evo_framework, dev, admin, treasury, resource_account, alice, bob);

        coin::transfer<COIN_1>(alice, signer::address_of(bob), 10 * pow(10, 8));
        coin::transfer<COIN_2>(bob, signer::address_of(alice), 10 * pow(10, 8));

        coin::register<COIN_2>(alice);
        coin::register<COIN_1>(bob);

        // create pair
        router::create_pair<COIN_1, COIN_2>(alice);

        // initialize fee on transfer of both tokens
        fee_on_transfer::initialize_fee_on_transfer_for_test<COIN_1>(alice, 0, 100, 100);
        fee_on_transfer::initialize_fee_on_transfer_for_test<COIN_2>(bob, 0, 200, 200);

        // register fee on transfer in the pairs
        router::register_fee_on_transfer_in_a_pair<COIN_1, COIN_1, COIN_2>(alice);
        router::register_fee_on_transfer_in_a_pair<COIN_2, COIN_1, COIN_2>(bob);

        let bob_liquidity_x = 10 * pow(10, 8);
        let bob_liquidity_y = 10 * pow(10, 8);
        let alice_liquidity_x = 2 * pow(10, 8);
        let alice_liquidity_y = 4 * pow(10, 8);

        // bob provider liquidity for COIN_1-COIN_2
        router::add_liquidity<COIN_1, COIN_2>(bob, bob_liquidity_x, bob_liquidity_y, 0, 0);

        let input_x = 2 * pow(10, 6);
        // COIN_1 is X and COIN_2 is Y -> Fees are in COIN_2
        router::swap_exact_input<COIN_1, COIN_2>(alice, input_x, 0);

        // COIN_2 is X and COIN_1 is Y -> Fees are in COIN_1
        router::swap_exact_input<COIN_2, COIN_1>(bob, input_x, 0);

        // treasury wallet receives the treasury fee
        debug::print<u64>(&coin::balance<COIN_1>(@treasury));
        debug::print<u64>(&coin::balance<COIN_2>(@treasury));

        // remove some liquidity
        router::remove_liquidity<COIN_1, COIN_2>(bob, 1 * pow(10, 6), 0, 0);
    }
        
    #[test(supra_framework = @0x1, evo_framework = @evo_framework, dev = @dev, admin= @admin, resource_account = @evo, treasury = @treasury, alice = @0x123, bob = @0x456)]
    // test ownerships transfer
    fun test_ownership_transfer(
        supra_framework: signer,
        evo_framework: &signer, 
        dev: &signer,
        admin: &signer,
        resource_account: &signer,
        treasury: &signer,
        bob: &signer,
        alice: &signer
    ) {
        setup_test_with_genesis(supra_framework, evo_framework, dev, admin, treasury, resource_account, alice, bob);

        // transfer admin:: previliges to bob
        admin::offer_admin_previliges(admin, signer::address_of(bob));
        admin::claim_admin_previliges(bob);
        assert!(admin::get_admin() == signer::address_of(bob), 1);

        // transfer admin:: previliges back to admin::
        admin::offer_admin_previliges(bob, signer::address_of(admin));
        admin::claim_admin_previliges(admin);
        assert!(admin::get_admin() == signer::address_of(admin), 2);

        // transfer admin:: previliges to alice but alice rejects it
        admin::offer_admin_previliges(admin, signer::address_of(alice));
        admin::reject_admin_previliges(alice);
        assert!(admin::get_admin() == signer::address_of(admin), 3);

        // transfer treasury previliges to alice
        admin::offer_treasury_previliges(admin, signer::address_of(alice));
        admin::claim_treasury_previliges(alice);
        assert!(admin::get_treasury_address() == signer::address_of(alice), 4);

        // transfer treasury previliges to bob but bob rejects it
        admin::offer_treasury_previliges(admin, signer::address_of(bob));
        admin::reject_treasury_previliges(bob);
        assert!(admin::get_treasury_address() == signer::address_of(alice), 6);
    }

    #[test(supra_framework = @0x1, evo_framework = @evo_framework, dev = @dev, admin= @admin, resource_account = @evo, treasury = @treasury, alice = @0x123, bob = @0x456)]
    // test update tiers
    fun test_update_tiers(
        supra_framework: signer,
        evo_framework: &signer, 
        dev: &signer,
        admin: &signer,
        resource_account: &signer,
        treasury: &signer,
        bob: &signer,
        alice: &signer
    ) {
        setup_test_with_genesis(supra_framework, evo_framework, dev, admin, treasury, resource_account, alice, bob);

        coin::transfer<COIN_1>(alice, signer::address_of(bob), 10 * pow(10, 8));
        coin::transfer<COIN_2>(bob, signer::address_of(alice), 10 * pow(10, 8));
        coin::register<COIN_2>(alice);
        coin::register<COIN_1>(bob);

        // create pair
        router::create_pair<COIN_1, COIN_2>(alice);
        // add liquidity
        let bob_liquidity_y = 10 * pow(10, 8);
        let alice_liquidity_x = 2 * pow(10, 8);
        router::add_liquidity<COIN_1, COIN_2>(bob, alice_liquidity_x, bob_liquidity_y, 0, 0);

        // update tiers to popular traded
        router::update_fee_tier<admin::PopularTraded, COIN_1, COIN_2>(admin);
        admin::is_valid_tier<admin::PopularTraded>();
        let (popular_traded_liquidity_fee, popular_traded_treasury_fee) = admin::get_popular_traded_tier_fees();
        let total_popular_traded_fee = popular_traded_liquidity_fee + popular_traded_treasury_fee;
        assert!(swap::token_fees<COIN_1, COIN_2>() == (total_popular_traded_fee), 1);

        // update tiers to stable
        router::update_fee_tier<admin::Stable, COIN_1, COIN_2>(admin);
        admin::is_valid_tier<admin::Stable>();
        let (stable_liquidity_fee, stable_treasury_fee) = admin::get_stable_tier_fees();
        let total_stable_fee = stable_liquidity_fee + stable_treasury_fee;
        assert!(swap::token_fees<COIN_1, COIN_2>() == (total_stable_fee), 2);

        // update tiers to very stable
        router::update_fee_tier<admin::VeryStable, COIN_1, COIN_2>(admin);
        admin::is_valid_tier<admin::VeryStable>();
        let (very_stable_liquidity_fee, very_stable_treasury_fee) = admin::get_very_stable_tier_fees();
        let total_very_stable_fee = very_stable_liquidity_fee + very_stable_treasury_fee;
        assert!(swap::token_fees<COIN_1, COIN_2>() == (total_very_stable_fee), 3);

        // update tiers back to universal
        router::update_fee_tier<admin::Universal, COIN_1, COIN_2>(admin);
        admin::is_valid_tier<admin::Universal>();
        let (universal_liquidity_fee, universal_treasury_fee) = admin::get_universal_tier_fees();
        let total_universal_fee = universal_liquidity_fee + universal_treasury_fee;
        assert!(swap::token_fees<COIN_1, COIN_2>() == (total_universal_fee), 4);

        // add fee on transfer
        fee_on_transfer::initialize_fee_on_transfer_for_test<COIN_1>(alice, 100, 100, 100);
        fee_on_transfer::initialize_fee_on_transfer_for_test<COIN_2>(bob, 100, 100, 100);
        router::register_fee_on_transfer_in_a_pair<COIN_1, COIN_1, COIN_2>(alice);
        router::register_fee_on_transfer_in_a_pair<COIN_2, COIN_1, COIN_2>(bob);

        // calculate fees
        let (dex_liquidity_fee, dex_treasury_fee) = swap::get_dex_fees_in_a_pair<COIN_1, COIN_2>();
        let dex_fees = dex_liquidity_fee + dex_treasury_fee;
        let coin_1_fee_on_transfer = fee_on_transfer::get_all_fee_on_transfer<COIN_1>();
        let coin_2_fee_on_transfer = fee_on_transfer::get_all_fee_on_transfer<COIN_2>();
        let expected_fees = dex_fees + coin_1_fee_on_transfer + coin_2_fee_on_transfer;
        // debug::print<u128>(&(expected_fees));
        // debug::print<u128>(&(swap::token_fees<COIN_1, COIN_2>()));
        assert!(swap::token_fees<COIN_1, COIN_2>() == (expected_fees), 5);

        // update tiers to popular traded
        router::update_fee_tier<admin::PopularTraded, COIN_1, COIN_2>(admin);
        let (popular_traded_liquidity_fee, popular_traded_treasury_fee) = admin::get_popular_traded_tier_fees();
        let total_popular_traded_fee = popular_traded_liquidity_fee + popular_traded_treasury_fee;
        let expected_updated_fees = coin_1_fee_on_transfer + coin_2_fee_on_transfer + total_popular_traded_fee;
        assert!(swap::token_fees<COIN_1, COIN_2>() == (expected_updated_fees), 6);

        // update tiers to stable
        router::update_fee_tier<admin::Stable, COIN_1, COIN_2>(admin);
        let (stable_liquidity_fee, stable_treasury_fee) = admin::get_stable_tier_fees();
        let total_stable_fee = stable_liquidity_fee + stable_treasury_fee;
        let expected_updated_fees_from_stable = coin_1_fee_on_transfer + coin_2_fee_on_transfer + total_stable_fee;
        assert!(swap::token_fees<COIN_1, COIN_2>() == (expected_updated_fees_from_stable), 7);

        // update tiers to very stable
        router::update_fee_tier<admin::VeryStable, COIN_1, COIN_2>(admin);
        let (very_stable_liquidity_fee, very_stable_treasury_fee) = admin::get_very_stable_tier_fees();
        let total_very_stable_fee = very_stable_liquidity_fee + very_stable_treasury_fee;
        let expected_updated_fees_from_very_stable = coin_1_fee_on_transfer + coin_2_fee_on_transfer + total_very_stable_fee;
        assert!(swap::token_fees<COIN_1, COIN_2>() == (expected_updated_fees_from_very_stable), 8);

        // update tiers back to universal
        router::update_fee_tier<admin::Universal, COIN_1, COIN_2>(admin);
        let (universal_liquidity_fee, universal_treasury_fee) = admin::get_universal_tier_fees();
        let total_universal_fee = universal_liquidity_fee + universal_treasury_fee;
        let expected_updated_fees_from_universal = coin_1_fee_on_transfer + coin_2_fee_on_transfer + total_universal_fee;
        assert!(swap::token_fees<COIN_1, COIN_2>() == (expected_updated_fees_from_universal), 9);

        // update dex fees universally and then update tiers to popular traded
        admin::set_dex_liquidity_fee(admin, 0);
        admin::set_dex_treasury_fee(admin, 0);
        assert!(admin::get_dex_fees() == 0, 10);
        router::update_fee_tier<admin::PopularTraded, COIN_1, COIN_2>(admin);
        let (popular_traded_liquidity_fee, popular_traded_treasury_fee) = admin::get_popular_traded_tier_fees();
        let total_popular_traded_fee = popular_traded_liquidity_fee + popular_traded_treasury_fee;
        let expected_updated_fees_from_popular_traded = coin_1_fee_on_transfer + coin_2_fee_on_transfer + total_popular_traded_fee;
        assert!(swap::token_fees<COIN_1, COIN_2>() == (expected_updated_fees_from_popular_traded), 10);
    }

    #[test(supra_framework = @0x1, evo_framework = @evo_framework, dev = @dev, admin= @admin, resource_account = @evo, treasury = @treasury, alice = @0x123, bob = @0x456)]
    // test multi-hop swap functions
    fun test_multi_hop_swaps(
        supra_framework: signer,
        evo_framework: &signer, 
        dev: &signer,
        admin: &signer,
        resource_account: &signer,
        treasury: &signer,
        bob: &signer,
        alice: &signer
    ) {
        setup_test_with_genesis(supra_framework, evo_framework, dev, admin, treasury, resource_account, alice, bob);

        coin::transfer<COIN_1>(alice, signer::address_of(bob), 10 * pow(10, 8));
        coin::transfer<COIN_2>(bob, signer::address_of(alice), 10 * pow(10, 8));

        coin::register<COIN_2>(alice);
        coin::register<COIN_1>(bob);

        // create pair
        // router::create_pair<COIN_1, COIN_2>(alice);
        router::create_pair<COIN_1, APT>(alice);
        router::create_pair<COIN_2, APT>(alice);

        let bob_liquidity_x = 2 * pow(10, 8);
        let bob_liquidity_y = 2 * pow(10, 8);
        let alice_liquidity_x = 2 * pow(10, 8);
        let alice_liquidity_y = 2 * pow(10, 8);

        // Add liquidity for COIN_1-APT and COIN_2-APT
        router::add_liquidity<COIN_1, APT>(bob, bob_liquidity_x, bob_liquidity_y, 0, 0);
        router::add_liquidity<COIN_2, APT>(alice, alice_liquidity_x, alice_liquidity_y, 0, 0);

        // swap without fee on transfer 
        let input_x = 2 * pow(10, 6);
        assert!(!swap::is_pair_created<COIN_1, COIN_2>() && !swap::is_pair_created<COIN_2, COIN_1>(), 1);
        router::swap_exact_input<COIN_1, APT>(alice, 10 * pow(10, 6), 0);
        router::swap_exact_input<COIN_2, APT>(alice, 10 * pow(10, 6), 0);
        router::swap_exact_input_with_one_intermediate_coin<COIN_1, COIN_2, APT>(alice, 10 * pow(10, 6), 0);
        router::swap_exact_input_with_apt_as_intermidiate<COIN_2, COIN_1>(alice, input_x, 0);

        // swap with fee on transfer
        fee_on_transfer::initialize_fee_on_transfer_for_test<COIN_1>(alice, 10, 20, 30);
        fee_on_transfer::initialize_fee_on_transfer_for_test<COIN_2>(bob, 35, 55, 15);

        router::register_fee_on_transfer_in_a_pair<COIN_1, COIN_1, APT>(alice);
        router::register_fee_on_transfer_in_a_pair<COIN_2, APT, COIN_2>(bob);

        router::swap_exact_input_with_one_intermediate_coin<COIN_1, COIN_2, APT>(alice, input_x, 0);
        router::swap_exact_input_with_apt_as_intermidiate<COIN_2, COIN_1>(alice, input_x, 0);

        // TODO: test swap_exact_input_with_two_intermediate_coins
    }

    // #[test(supra_framework = @0x1, evo_framework = @evo_framework, dev = @dev, admin= @admin, resource_account = @evo, treasury = @treasury, alice = @0x123, bob = @0x456)]
    // // test merge function
    // fun test_merge(
    //     supra_framework: signer,
    //     evo_framework: &signer, 
    //     dev: &signer,
    //     admin: &signer,
    //     resource_account: &signer,
    //     treasury: &signer,
    //     bob: &signer,
    //     alice: &signer
    // ) {
    //     setup_test_with_genesis(supra_framework, evo_framework, dev, admin, treasury, resource_account, alice, bob);

    //     coin::transfer<COIN_1>(alice, signer::address_of(bob), 10 * pow(10, 8));
    //     coin::transfer<COIN_2>(bob, signer::address_of(alice), 10 * pow(10, 8));

    //     coin::register<COIN_2>(alice);
    //     coin::register<COIN_1>(bob);

    //     // create pair
    //     router_v2::create_pair<COIN_1, COIN_2>(alice);
    //     router::create_pair<COIN_1, COIN_2>(alice);

    //     let bob_liquidity_x = 2 * pow(10, 8);
    //     let bob_liquidity_y = 2 * pow(10, 8);
    //     let alice_liquidity_x = 2 * pow(10, 8);
    //     let alice_liquidity_y = 2 * pow(10, 8);

    //     // Add liquidity for COIN_1-COIN_2
    //     router_v2::add_liquidity<COIN_1, COIN_2>(bob, bob_liquidity_x, bob_liquidity_y, 0, 0);

    //     // swap without fee on transfer 
    //     let input_x = 2 * pow(10, 6);
    //     router::swap_exact_input<COIN_1, COIN_2>(alice, input_x, 0);

    //     // merge
    //     router::merge_to<COIN_2>(bob);
    // }

    // #[test(dev = @dev_2, admin= @admin, resource_account = @evo, treasury = @treasury, bob = @0x12345, alice = @0x12346)]
    // fun test_add_liquidity(
    //     dev: &signer,
    //     admin: &signer,
    //     resource_account: &signer,
    //     treasury: &signer,
    //     bob: &signer,
    //     alice: &signer,
    // ) {
    //     account::create_account_for_test(signer::address_of(bob));
    //     account::create_account_for_test(signer::address_of(alice));

    //     setup_test_with_genesis(dev, admin, treasury, resource_account);

    //     let coin_owner = test_coins::init_coins();

    //     test_coins::register_and_mint<TestCAKE>(&coin_owner, bob, 100 * pow(10, 8));
    //     test_coins::register_and_mint<TestBUSD>(&coin_owner, bob, 100 * pow(10, 8));
    //     test_coins::register_and_mint<TestCAKE>(&coin_owner, alice, 100 * pow(10, 8));
    //     test_coins::register_and_mint<TestBUSD>(&coin_owner, alice, 100 * pow(10, 8));

    //     let bob_liquidity_x = 5 * pow(10, 8);
    //     let bob_liquidity_y = 10 * pow(10, 8);
    //     let alice_liquidity_x = 2 * pow(10, 8);
    //     let alice_liquidity_y = 4 * pow(10, 8);

    //     // bob provider liquidity for 5:10 CAKE-BUSD
    //     router::add_liquidity<TestCAKE, TestBUSD>(bob, bob_liquidity_x, bob_liquidity_y, 0, 0);
    //     router::add_liquidity<TestCAKE, TestBUSD>(alice, alice_liquidity_x, alice_liquidity_y, 0, 0);

    //     let (balance_y, balance_x) = swap::token_balances<TestBUSD, TestCAKE>();
    //     let (reserve_y, reserve_x, _) = swap::token_reserves<TestBUSD, TestCAKE>();
    //     let resource_account_lp_balance = coin::balance<LPToken<TestBUSD, TestCAKE>>(signer::address_of(resource_account));
    //     let bob_lp_balance = coin::balance<LPToken<TestBUSD, TestCAKE>>(signer::address_of(bob));
    //     let alice_lp_balance = coin::balance<LPToken<TestBUSD, TestCAKE>>(signer::address_of(alice));

    //     let resource_account_suppose_lp_balance = MINIMUM_LIQUIDITY;
    //     let bob_suppose_lp_balance = math::sqrt(((bob_liquidity_x as u128) * (bob_liquidity_y as u128))) - MINIMUM_LIQUIDITY;
    //     let total_supply = bob_suppose_lp_balance + MINIMUM_LIQUIDITY;
    //     let alice_suppose_lp_balance = math::min((alice_liquidity_x as u128) * total_supply / (bob_liquidity_x as u128), (alice_liquidity_y as u128) * total_supply / (bob_liquidity_y as u128));

    //     assert!(balance_x == bob_liquidity_x + alice_liquidity_x, 99);
    //     assert!(reserve_x == bob_liquidity_x + alice_liquidity_x, 98);
    //     assert!(balance_y == bob_liquidity_y + alice_liquidity_y, 97);
    //     assert!(reserve_y == bob_liquidity_y + alice_liquidity_y, 96);

    //     assert!(bob_lp_balance == (bob_suppose_lp_balance as u64), 95);
    //     assert!(alice_lp_balance == (alice_suppose_lp_balance as u64), 94);
    //     assert!(resource_account_lp_balance == (resource_account_suppose_lp_balance as u64), 93);
    // }

    // #[test(dev = @dev, admin= @admin, resource_account = @evo, treasury = @treasury, bob = @0x12345, alice = @0x12346)]
    // fun test_add_liquidity_with_less_x_ratio(
    //     dev: &signer,
    //     admin: &signer,
    //     resource_account: &signer,
    //     treasury: &signer,
    //     bob: &signer,
    //     alice: &signer,
    // ) {
    //     account::create_account_for_test(signer::address_of(bob));
    //     account::create_account_for_test(signer::address_of(alice));

    //     setup_test_with_genesis(dev, admin, treasury, resource_account);

    //     let coin_owner = test_coins::init_coins();

    //     test_coins::register_and_mint<TestCAKE>(&coin_owner, bob, 200 * pow(10, 8));
    //     test_coins::register_and_mint<TestBUSD>(&coin_owner, bob, 200 * pow(10, 8));

    //     let bob_liquidity_x = 5 * pow(10, 8);
    //     let bob_liquidity_y = 10 * pow(10, 8);

    //     // bob provider liquidity for 5:10 CAKE-BUSD
    //     router::add_liquidity<TestCAKE, TestBUSD>(bob, bob_liquidity_x, bob_liquidity_y, 0, 0);

    //     let bob_token_x_before_balance = coin::balance<TestCAKE>(signer::address_of(bob));
    //     let bob_token_y_before_balance = coin::balance<TestBUSD>(signer::address_of(bob));

    //     let bob_add_liquidity_x = 1 * pow(10, 8);
    //     let bob_add_liquidity_y = 5 * pow(10, 8);
    //     router::add_liquidity<TestCAKE, TestBUSD>(bob, bob_add_liquidity_x, bob_add_liquidity_y, 0, 0);

    //     let bob_added_liquidity_x = bob_add_liquidity_x;
    //     let bob_added_liquidity_y = (bob_add_liquidity_x as u128) * (bob_liquidity_y as u128) / (bob_liquidity_x as u128);

    //     let bob_token_x_after_balance = coin::balance<TestCAKE>(signer::address_of(bob));
    //     let bob_token_y_after_balance = coin::balance<TestBUSD>(signer::address_of(bob));
    //     let bob_lp_balance = coin::balance<LPToken<TestBUSD, TestCAKE>>(signer::address_of(bob));
    //     let resource_account_lp_balance = coin::balance<LPToken<TestBUSD, TestCAKE>>(signer::address_of(resource_account));

    //     let resource_account_suppose_lp_balance = MINIMUM_LIQUIDITY;
    //     let bob_suppose_lp_balance = math::sqrt(((bob_liquidity_x as u128) * (bob_liquidity_y as u128))) - MINIMUM_LIQUIDITY;
    //     let total_supply = bob_suppose_lp_balance + MINIMUM_LIQUIDITY;
    //     bob_suppose_lp_balance = bob_suppose_lp_balance + math::min((bob_add_liquidity_x as u128) * total_supply / (bob_liquidity_x as u128), (bob_add_liquidity_y as u128) * total_supply / (bob_liquidity_y as u128));

    //     assert!((bob_token_x_before_balance - bob_token_x_after_balance) == (bob_added_liquidity_x as u64), 99);
    //     assert!((bob_token_y_before_balance - bob_token_y_after_balance) == (bob_added_liquidity_y as u64), 98);
    //     assert!(bob_lp_balance == (bob_suppose_lp_balance as u64), 97);
    //     assert!(resource_account_lp_balance == (resource_account_suppose_lp_balance as u64), 96);
    // }

    // #[test(dev = @dev, admin= @admin, resource_account = @evo, treasury = @treasury, bob = @0x12345, alice = @0x12346)]
    // #[expected_failure(abort_code = 3)]
    // fun test_add_liquidity_with_less_x_ratio_and_less_than_y_min(
    //     dev: &signer,
    //     admin: &signer,
    //     resource_account: &signer,
    //     treasury: &signer,
    //     bob: &signer,
    //     alice: &signer,
    // ) {
    //     account::create_account_for_test(signer::address_of(bob));
    //     account::create_account_for_test(signer::address_of(alice));

    //     setup_test_with_genesis(dev, admin, treasury, resource_account);

    //     let coin_owner = test_coins::init_coins();

    //     test_coins::register_and_mint<TestCAKE>(&coin_owner, bob, 200 * pow(10, 8));
    //     test_coins::register_and_mint<TestBUSD>(&coin_owner, bob, 200 * pow(10, 8));

    //     let initial_reserve_x = 5 * pow(10, 8);
    //     let initial_reserve_y = 10 * pow(10, 8);

    //     // bob provider liquidity for 5:10 CAKE-BUSD
    //     router::add_liquidity<TestCAKE, TestBUSD>(bob, initial_reserve_x, initial_reserve_y, 0, 0);

    //     let bob_add_liquidity_x = 1 * pow(10, 8);
    //     let bob_add_liquidity_y = 5 * pow(10, 8);
    //     router::add_liquidity<TestCAKE, TestBUSD>(bob, bob_add_liquidity_x, bob_add_liquidity_y, 0, 4 * pow(10, 8));
    // }

    // #[test(dev = @dev, admin= @admin, resource_account = @evo, treasury = @treasury, bob = @0x12345, alice = @0x12346)]
    // fun test_add_liquidity_with_less_y_ratio(
    //     dev: &signer,
    //     admin: &signer,
    //     resource_account: &signer,
    //     treasury: &signer,
    //     bob: &signer,
    //     alice: &signer,
    // ) {
    //     account::create_account_for_test(signer::address_of(bob));
    //     account::create_account_for_test(signer::address_of(alice));

    //     setup_test_with_genesis(dev, admin, treasury, resource_account);

    //     let coin_owner = test_coins::init_coins();

    //     test_coins::register_and_mint<TestCAKE>(&coin_owner, bob, 200 * pow(10, 8));
    //     test_coins::register_and_mint<TestBUSD>(&coin_owner, bob, 200 * pow(10, 8));

    //     let bob_liquidity_x = 5 * pow(10, 8);
    //     let bob_liquidity_y = 10 * pow(10, 8);

    //     // bob provider liquidity for 5:10 CAKE-BUSD
    //     router::add_liquidity<TestCAKE, TestBUSD>(bob, bob_liquidity_x, bob_liquidity_y, 0, 0);

    //     let bob_token_x_before_balance = coin::balance<TestCAKE>(signer::address_of(bob));
    //     let bob_token_y_before_balance = coin::balance<TestBUSD>(signer::address_of(bob));

    //     let bob_add_liquidity_x = 5 * pow(10, 8);
    //     let bob_add_liquidity_y = 4 * pow(10, 8);
    //     router::add_liquidity<TestCAKE, TestBUSD>(bob, bob_add_liquidity_x, bob_add_liquidity_y, 0, 0);

    //     let bob_added_liquidity_x = (bob_add_liquidity_y as u128) * (bob_liquidity_x as u128) / (bob_liquidity_y as u128);
    //     let bob_added_liquidity_y = bob_add_liquidity_y;

    //     let bob_token_x_after_balance = coin::balance<TestCAKE>(signer::address_of(bob));
    //     let bob_token_y_after_balance = coin::balance<TestBUSD>(signer::address_of(bob));
    //     let bob_lp_balance = coin::balance<LPToken<TestBUSD, TestCAKE>>(signer::address_of(bob));
    //     let resource_account_lp_balance = coin::balance<LPToken<TestBUSD, TestCAKE>>(signer::address_of(resource_account));

    //     let resource_account_suppose_lp_balance = MINIMUM_LIQUIDITY;
    //     let bob_suppose_lp_balance = math::sqrt(((bob_liquidity_x as u128) * (bob_liquidity_y as u128))) - MINIMUM_LIQUIDITY;
    //     let total_supply = bob_suppose_lp_balance + MINIMUM_LIQUIDITY;
    //     bob_suppose_lp_balance = bob_suppose_lp_balance + math::min((bob_add_liquidity_x as u128) * total_supply / (bob_liquidity_x as u128), (bob_add_liquidity_y as u128) * total_supply / (bob_liquidity_y as u128));


    //     assert!((bob_token_x_before_balance - bob_token_x_after_balance) == (bob_added_liquidity_x as u64), 99);
    //     assert!((bob_token_y_before_balance - bob_token_y_after_balance) == (bob_added_liquidity_y as u64), 98);
    //     assert!(bob_lp_balance == (bob_suppose_lp_balance as u64), 97);
    //     assert!(resource_account_lp_balance == (resource_account_suppose_lp_balance as u64), 96);
    // }

    // #[test(dev = @dev, admin= @admin, resource_account = @evo, treasury = @treasury, bob = @0x12345, alice = @0x12346)]
    // #[expected_failure(abort_code = 2)]
    // fun test_add_liquidity_with_less_y_ratio_and_less_than_x_min(
    //     dev: &signer,
    //     admin: &signer,
    //     resource_account: &signer,
    //     treasury: &signer,
    //     bob: &signer,
    //     alice: &signer,
    // ) {
    //     account::create_account_for_test(signer::address_of(bob));
    //     account::create_account_for_test(signer::address_of(alice));

    //     setup_test_with_genesis(dev, admin, treasury, resource_account);

    //     let coin_owner = test_coins::init_coins();

    //     test_coins::register_and_mint<TestCAKE>(&coin_owner, bob, 200 * pow(10, 8));
    //     test_coins::register_and_mint<TestBUSD>(&coin_owner, bob, 200 * pow(10, 8));

    //     let initial_reserve_x = 5 * pow(10, 8);
    //     let initial_reserve_y = 10 * pow(10, 8);

    //     // bob provider liquidity for 5:10 CAKE-BUSD
    //     router::add_liquidity<TestCAKE, TestBUSD>(bob, initial_reserve_x, initial_reserve_y, 0, 0);

    //     let bob_add_liquidity_x = 5 * pow(10, 8);
    //     let bob_add_liquidity_y = 4 * pow(10, 8);
    //     router::add_liquidity<TestCAKE, TestBUSD>(bob, bob_add_liquidity_x, bob_add_liquidity_y, 5 * pow(10, 8), 0);
    // }

    // #[test(dev = @dev, admin= @admin, resource_account = @evo, treasury = @treasury, bob = @0x12341, alice = @0x12342)]
    // fun test_remove_liquidity(
    //     dev: &signer,
    //     admin: &signer,
    //     resource_account: &signer,
    //     treasury: &signer,
    //     bob: &signer,
    //     alice: &signer,
    // ) {
    //     account::create_account_for_test(signer::address_of(bob));
    //     account::create_account_for_test(signer::address_of(alice));
    //     setup_test_with_genesis(dev, admin, treasury, resource_account);

    //     let coin_owner = test_coins::init_coins();

    //     test_coins::register_and_mint<TestCAKE>(&coin_owner, bob, 100 * pow(10, 8));
    //     test_coins::register_and_mint<TestCAKE>(&coin_owner, alice, 100 * pow(10, 8));

    //     test_coins::register_and_mint<TestBUSD>(&coin_owner, bob, 100 * pow(10, 8));
    //     test_coins::register_and_mint<TestBUSD>(&coin_owner, alice, 100 * pow(10, 8));

    //     let bob_add_liquidity_x = 5 * pow(10, 8);
    //     let bob_add_liquidity_y = 10 * pow(10, 8);

    //     let alice_add_liquidity_x = 2 * pow(10, 8);
    //     let alice_add_liquidity_y = 4 * pow(10, 8);

    //     // bob provider liquidity for 5:10 CAKE-BUSD
    //     router::add_liquidity<TestCAKE, TestBUSD>(bob, bob_add_liquidity_x, bob_add_liquidity_y, 0, 0);
    //     router::add_liquidity<TestCAKE, TestBUSD>(alice, alice_add_liquidity_x, alice_add_liquidity_y, 0, 0);

    //     let bob_suppose_lp_balance = math::sqrt(((bob_add_liquidity_x as u128) * (bob_add_liquidity_y as u128))) - MINIMUM_LIQUIDITY;
    //     let suppose_total_supply = bob_suppose_lp_balance + MINIMUM_LIQUIDITY;
    //     let alice_suppose_lp_balance = math::min((alice_add_liquidity_x as u128) * suppose_total_supply / (bob_add_liquidity_x as u128), (alice_add_liquidity_y as u128) * suppose_total_supply / (bob_add_liquidity_y as u128));
    //     suppose_total_supply = suppose_total_supply + alice_suppose_lp_balance;
    //     let suppose_reserve_x = bob_add_liquidity_x + alice_add_liquidity_x;
    //     let suppose_reserve_y = bob_add_liquidity_y + alice_add_liquidity_y;

    //     let bob_lp_balance = coin::balance<LPToken<TestBUSD, TestCAKE>>(signer::address_of(bob));
    //     let alice_lp_balance = coin::balance<LPToken<TestBUSD, TestCAKE>>(signer::address_of(alice));

    //     assert!((bob_suppose_lp_balance as u64) == bob_lp_balance, 99);
    //     assert!((alice_suppose_lp_balance as u64) == alice_lp_balance, 98);

    //     let alice_token_x_before_balance = coin::balance<TestCAKE>(signer::address_of(alice));
    //     let alice_token_y_before_balance = coin::balance<TestBUSD>(signer::address_of(alice));
    //     let bob_token_x_before_balance = coin::balance<TestCAKE>(signer::address_of(bob));
    //     let bob_token_y_before_balance = coin::balance<TestBUSD>(signer::address_of(bob));

    //     router::remove_liquidity<TestCAKE, TestBUSD>(bob, (bob_suppose_lp_balance as u64), 0, 0);
    //     let bob_remove_liquidity_x = ((suppose_reserve_x) as u128) * bob_suppose_lp_balance / suppose_total_supply;
    //     let bob_remove_liquidity_y = ((suppose_reserve_y) as u128) * bob_suppose_lp_balance / suppose_total_supply;
    //     suppose_total_supply = suppose_total_supply - bob_suppose_lp_balance;
    //     suppose_reserve_x = suppose_reserve_x - (bob_remove_liquidity_x as u64);
    //     suppose_reserve_y = suppose_reserve_y - (bob_remove_liquidity_y as u64);

    //     router::remove_liquidity<TestCAKE, TestBUSD>(alice, (alice_suppose_lp_balance as u64), 0, 0);
    //     let alice_remove_liquidity_x = ((suppose_reserve_x) as u128) * alice_suppose_lp_balance / suppose_total_supply;
    //     let alice_remove_liquidity_y = ((suppose_reserve_y) as u128) * alice_suppose_lp_balance / suppose_total_supply;
    //     suppose_reserve_x = suppose_reserve_x - (alice_remove_liquidity_x as u64);
    //     suppose_reserve_y = suppose_reserve_y - (alice_remove_liquidity_y as u64);

    //     let alice_lp_after_balance = coin::balance<LPToken<TestBUSD, TestCAKE>>(signer::address_of(alice));
    //     let bob_lp_after_balance = coin::balance<LPToken<TestBUSD, TestCAKE>>(signer::address_of(bob));
    //     let alice_token_x_after_balance = coin::balance<TestCAKE>(signer::address_of(alice));
    //     let alice_token_y_after_balance = coin::balance<TestBUSD>(signer::address_of(alice));
    //     let bob_token_x_after_balance = coin::balance<TestCAKE>(signer::address_of(bob));
    //     let bob_token_y_after_balance = coin::balance<TestBUSD>(signer::address_of(bob));
    //     let (balance_y, balance_x) = swap::token_balances<TestBUSD, TestCAKE>();
    //     let (reserve_y, reserve_x, _) = swap::token_reserves<TestBUSD, TestCAKE>();
    //     let total_supply = std::option::get_with_default(
    //         &coin::supply<LPToken<TestBUSD, TestCAKE>>(),
    //         0u128
    //     );

    //     assert!((alice_token_x_after_balance - alice_token_x_before_balance) == (alice_remove_liquidity_x as u64), 97);
    //     assert!((alice_token_y_after_balance - alice_token_y_before_balance) == (alice_remove_liquidity_y as u64), 96);
    //     assert!((bob_token_x_after_balance - bob_token_x_before_balance) == (bob_remove_liquidity_x as u64), 95);
    //     assert!((bob_token_y_after_balance - bob_token_y_before_balance) == (bob_remove_liquidity_y as u64), 94);
    //     assert!(alice_lp_after_balance == 0, 93);
    //     assert!(bob_lp_after_balance == 0, 92);
    //     assert!(balance_x == suppose_reserve_x, 91);
    //     assert!(balance_y == suppose_reserve_y, 90);
    //     assert!(reserve_x == suppose_reserve_x, 89);
    //     assert!(reserve_y == suppose_reserve_y, 88);
    //     assert!(total_supply == MINIMUM_LIQUIDITY, 87);
    // }

    // #[test(dev = @dev, admin= @admin, resource_account = @evo, treasury = @treasury, user1 = @0x12341, user2 = @0x12342, user3 = @0x12343, user4 = @0x12344)]
    // fun test_remove_liquidity_with_more_user(
    //     dev: &signer,
    //     admin: &signer,
    //     resource_account: &signer,
    //     treasury: &signer,
    //     user1: &signer,
    //     user2: &signer,
    //     user3: &signer,
    //     user4: &signer,
    // ) {
    //     account::create_account_for_test(signer::address_of(user1));
    //     account::create_account_for_test(signer::address_of(user2));
    //     account::create_account_for_test(signer::address_of(user3));
    //     account::create_account_for_test(signer::address_of(user4));
    //     setup_test_with_genesis(dev, admin, treasury, resource_account);

    //     let coin_owner = test_coins::init_coins();

    //     test_coins::register_and_mint<TestCAKE>(&coin_owner, user1, 100 * pow(10, 8));
    //     test_coins::register_and_mint<TestCAKE>(&coin_owner, user2, 100 * pow(10, 8));
    //     test_coins::register_and_mint<TestCAKE>(&coin_owner, user3, 100 * pow(10, 8));
    //     test_coins::register_and_mint<TestCAKE>(&coin_owner, user4, 100 * pow(10, 8));

    //     test_coins::register_and_mint<TestBUSD>(&coin_owner, user1, 100 * pow(10, 8));
    //     test_coins::register_and_mint<TestBUSD>(&coin_owner, user2, 100 * pow(10, 8));
    //     test_coins::register_and_mint<TestBUSD>(&coin_owner, user3, 100 * pow(10, 8));
    //     test_coins::register_and_mint<TestBUSD>(&coin_owner, user4, 100 * pow(10, 8));

    //     let user1_add_liquidity_x = 5 * pow(10, 8);
    //     let user1_add_liquidity_y = 10 * pow(10, 8);

    //     let user2_add_liquidity_x = 2 * pow(10, 8);
    //     let user2_add_liquidity_y = 4 * pow(10, 8);

    //     let user3_add_liquidity_x = 25 * pow(10, 8);
    //     let user3_add_liquidity_y = 50 * pow(10, 8);

    //     let user4_add_liquidity_x = 45 * pow(10, 8);
    //     let user4_add_liquidity_y = 90 * pow(10, 8);

    //     // bob provider liquidity for 5:10 CAKE-BUSD
    //     router::add_liquidity<TestCAKE, TestBUSD>(user1, user1_add_liquidity_x, user1_add_liquidity_y, 0, 0);
    //     router::add_liquidity<TestCAKE, TestBUSD>(user2, user2_add_liquidity_x, user2_add_liquidity_y, 0, 0);
    //     router::add_liquidity<TestCAKE, TestBUSD>(user3, user3_add_liquidity_x, user3_add_liquidity_y, 0, 0);
    //     router::add_liquidity<TestCAKE, TestBUSD>(user4, user4_add_liquidity_x, user4_add_liquidity_y, 0, 0);

    //     let user1_suppose_lp_balance = math::sqrt(((user1_add_liquidity_x as u128) * (user1_add_liquidity_y as u128))) - MINIMUM_LIQUIDITY;
    //     let suppose_total_supply = user1_suppose_lp_balance + MINIMUM_LIQUIDITY;
    //     let suppose_reserve_x = user1_add_liquidity_x;
    //     let suppose_reserve_y = user1_add_liquidity_y;
    //     let user2_suppose_lp_balance = math::min((user2_add_liquidity_x as u128) * suppose_total_supply / (suppose_reserve_x as u128), (user2_add_liquidity_y as u128) * suppose_total_supply / (suppose_reserve_y as u128));
    //     suppose_total_supply = suppose_total_supply + user2_suppose_lp_balance;
    //     suppose_reserve_x = suppose_reserve_x + user2_add_liquidity_x;
    //     suppose_reserve_y = suppose_reserve_y + user2_add_liquidity_y;
    //     let user3_suppose_lp_balance = math::min((user3_add_liquidity_x as u128) * suppose_total_supply / (suppose_reserve_x as u128), (user3_add_liquidity_y as u128) * suppose_total_supply / (suppose_reserve_y as u128));
    //     suppose_total_supply = suppose_total_supply + user3_suppose_lp_balance;
    //     suppose_reserve_x = suppose_reserve_x + user3_add_liquidity_x;
    //     suppose_reserve_y = suppose_reserve_y + user3_add_liquidity_y;
    //     let user4_suppose_lp_balance = math::min((user4_add_liquidity_x as u128) * suppose_total_supply / (suppose_reserve_x as u128), (user4_add_liquidity_y as u128) * suppose_total_supply / (suppose_reserve_y as u128));
    //     suppose_total_supply = suppose_total_supply + user4_suppose_lp_balance;
    //     suppose_reserve_x = suppose_reserve_x + user4_add_liquidity_x;
    //     suppose_reserve_y = suppose_reserve_y + user4_add_liquidity_y;

    //     let user1_lp_balance = coin::balance<LPToken<TestBUSD, TestCAKE>>(signer::address_of(user1));
    //     let user2_lp_balance = coin::balance<LPToken<TestBUSD, TestCAKE>>(signer::address_of(user2));
    //     let user3_lp_balance = coin::balance<LPToken<TestBUSD, TestCAKE>>(signer::address_of(user3));
    //     let user4_lp_balance = coin::balance<LPToken<TestBUSD, TestCAKE>>(signer::address_of(user4));

    //     assert!((user1_suppose_lp_balance as u64) == user1_lp_balance, 99);
    //     assert!((user2_suppose_lp_balance as u64) == user2_lp_balance, 98);
    //     assert!((user3_suppose_lp_balance as u64) == user3_lp_balance, 97);
    //     assert!((user4_suppose_lp_balance as u64) == user4_lp_balance, 96);

    //     let user1_token_x_before_balance = coin::balance<TestCAKE>(signer::address_of(user1));
    //     let user1_token_y_before_balance = coin::balance<TestBUSD>(signer::address_of(user1));
    //     let user2_token_x_before_balance = coin::balance<TestCAKE>(signer::address_of(user2));
    //     let user2_token_y_before_balance = coin::balance<TestBUSD>(signer::address_of(user2));
    //     let user3_token_x_before_balance = coin::balance<TestCAKE>(signer::address_of(user3));
    //     let user3_token_y_before_balance = coin::balance<TestBUSD>(signer::address_of(user3));
    //     let user4_token_x_before_balance = coin::balance<TestCAKE>(signer::address_of(user4));
    //     let user4_token_y_before_balance = coin::balance<TestBUSD>(signer::address_of(user4));

    //     router::remove_liquidity<TestCAKE, TestBUSD>(user1, (user1_suppose_lp_balance as u64), 0, 0);
    //     let user1_remove_liquidity_x = ((suppose_reserve_x) as u128) * user1_suppose_lp_balance / suppose_total_supply;
    //     let user1_remove_liquidity_y = ((suppose_reserve_y) as u128) * user1_suppose_lp_balance / suppose_total_supply;
    //     suppose_total_supply = suppose_total_supply - user1_suppose_lp_balance;
    //     suppose_reserve_x = suppose_reserve_x - (user1_remove_liquidity_x as u64);
    //     suppose_reserve_y = suppose_reserve_y - (user1_remove_liquidity_y as u64);

    //     router::remove_liquidity<TestCAKE, TestBUSD>(user2, (user2_suppose_lp_balance as u64), 0, 0);
    //     let user2_remove_liquidity_x = ((suppose_reserve_x) as u128) * user2_suppose_lp_balance / suppose_total_supply;
    //     let user2_remove_liquidity_y = ((suppose_reserve_y) as u128) * user2_suppose_lp_balance / suppose_total_supply;
    //     suppose_total_supply = suppose_total_supply - user2_suppose_lp_balance;
    //     suppose_reserve_x = suppose_reserve_x - (user2_remove_liquidity_x as u64);
    //     suppose_reserve_y = suppose_reserve_y - (user2_remove_liquidity_y as u64);

    //     router::remove_liquidity<TestCAKE, TestBUSD>(user3, (user3_suppose_lp_balance as u64), 0, 0);
    //     let user3_remove_liquidity_x = ((suppose_reserve_x) as u128) * user3_suppose_lp_balance / suppose_total_supply;
    //     let user3_remove_liquidity_y = ((suppose_reserve_y) as u128) * user3_suppose_lp_balance / suppose_total_supply;
    //     suppose_total_supply = suppose_total_supply - user3_suppose_lp_balance;
    //     suppose_reserve_x = suppose_reserve_x - (user3_remove_liquidity_x as u64);
    //     suppose_reserve_y = suppose_reserve_y - (user3_remove_liquidity_y as u64);

    //     router::remove_liquidity<TestCAKE, TestBUSD>(user4, (user4_suppose_lp_balance as u64), 0, 0);
    //     let user4_remove_liquidity_x = ((suppose_reserve_x) as u128) * user4_suppose_lp_balance / suppose_total_supply;
    //     let user4_remove_liquidity_y = ((suppose_reserve_y) as u128) * user4_suppose_lp_balance / suppose_total_supply;
    //     suppose_reserve_x = suppose_reserve_x - (user4_remove_liquidity_x as u64);
    //     suppose_reserve_y = suppose_reserve_y - (user4_remove_liquidity_y as u64);

    //     let user1_lp_after_balance = coin::balance<LPToken<TestBUSD, TestCAKE>>(signer::address_of(user1));
    //     let user2_lp_after_balance = coin::balance<LPToken<TestBUSD, TestCAKE>>(signer::address_of(user2));
    //     let user3_lp_after_balance = coin::balance<LPToken<TestBUSD, TestCAKE>>(signer::address_of(user3));
    //     let user4_lp_after_balance = coin::balance<LPToken<TestBUSD, TestCAKE>>(signer::address_of(user4));

    //     let user1_token_x_after_balance = coin::balance<TestCAKE>(signer::address_of(user1));
    //     let user1_token_y_after_balance = coin::balance<TestBUSD>(signer::address_of(user1));
    //     let user2_token_x_after_balance = coin::balance<TestCAKE>(signer::address_of(user2));
    //     let user2_token_y_after_balance = coin::balance<TestBUSD>(signer::address_of(user2));
    //     let user3_token_x_after_balance = coin::balance<TestCAKE>(signer::address_of(user3));
    //     let user3_token_y_after_balance = coin::balance<TestBUSD>(signer::address_of(user3));
    //     let user4_token_x_after_balance = coin::balance<TestCAKE>(signer::address_of(user4));
    //     let user4_token_y_after_balance = coin::balance<TestBUSD>(signer::address_of(user4));

    //     let (balance_y, balance_x) = swap::token_balances<TestBUSD, TestCAKE>();
    //     let (reserve_y, reserve_x, _) = swap::token_reserves<TestBUSD, TestCAKE>();
    //     let total_supply = swap::total_lp_supply<TestBUSD, TestCAKE>();

    //     assert!((user1_token_x_after_balance - user1_token_x_before_balance) == (user1_remove_liquidity_x as u64), 95);
    //     assert!((user1_token_y_after_balance - user1_token_y_before_balance) == (user1_remove_liquidity_y as u64), 94);
    //     assert!((user2_token_x_after_balance - user2_token_x_before_balance) == (user2_remove_liquidity_x as u64), 93);
    //     assert!((user2_token_y_after_balance - user2_token_y_before_balance) == (user2_remove_liquidity_y as u64), 92);
    //     assert!((user3_token_x_after_balance - user3_token_x_before_balance) == (user3_remove_liquidity_x as u64), 91);
    //     assert!((user3_token_y_after_balance - user3_token_y_before_balance) == (user3_remove_liquidity_y as u64), 90);
    //     assert!((user4_token_x_after_balance - user4_token_x_before_balance) == (user4_remove_liquidity_x as u64), 89);
    //     assert!((user4_token_y_after_balance - user4_token_y_before_balance) == (user4_remove_liquidity_y as u64), 88);
    //     assert!(user1_lp_after_balance == 0, 87);
    //     assert!(user2_lp_after_balance == 0, 86);
    //     assert!(user3_lp_after_balance == 0, 85);
    //     assert!(user4_lp_after_balance == 0, 84);
    //     assert!(balance_x == suppose_reserve_x, 83);
    //     assert!(balance_y == suppose_reserve_y, 82);
    //     assert!(reserve_x == suppose_reserve_x, 81);
    //     assert!(reserve_y == suppose_reserve_y, 80);
    //     assert!(total_supply == MINIMUM_LIQUIDITY, 79);
    // }

    // #[test(dev = @dev, admin= @admin, resource_account = @evo, treasury = @treasury, bob = @0x12341, alice = @0x12342)]
    // #[expected_failure(abort_code = 10)]
    // fun test_remove_liquidity_imbalance(
    //     dev: &signer,
    //     admin: &signer,
    //     resource_account: &signer,
    //     treasury: &signer,
    //     bob: &signer,
    //     alice: &signer,
    // ) {
    //     account::create_account_for_test(signer::address_of(bob));
    //     account::create_account_for_test(signer::address_of(alice));
    //     setup_test_with_genesis(dev, admin, treasury, resource_account);

    //     let coin_owner = test_coins::init_coins();

    //     test_coins::register_and_mint<TestCAKE>(&coin_owner, bob, 100 * pow(10, 8));
    //     test_coins::register_and_mint<TestCAKE>(&coin_owner, alice, 100 * pow(10, 8));

    //     test_coins::register_and_mint<TestBUSD>(&coin_owner, bob, 100 * pow(10, 8));
    //     test_coins::register_and_mint<TestBUSD>(&coin_owner, alice, 100 * pow(10, 8));

    //     let bob_liquidity_x = 5 * pow(10, 8);
    //     let bob_liquidity_y = 10 * pow(10, 8);

    //     let alice_liquidity_x = 1;
    //     let alice_liquidity_y = 2;

    //     // bob provider liquidity for 5:10 CAKE-BUSD
    //     router::add_liquidity<TestCAKE, TestBUSD>(bob, bob_liquidity_x, bob_liquidity_y, 0, 0);
    //     router::add_liquidity<TestCAKE, TestBUSD>(alice, alice_liquidity_x, alice_liquidity_y, 0, 0);

    //     let bob_lp_balance = coin::balance<LPToken<TestBUSD, TestCAKE>>(signer::address_of(bob));
    //     let alice_lp_balance = coin::balance<LPToken<TestBUSD, TestCAKE>>(signer::address_of(alice));

    //     router::remove_liquidity<TestCAKE, TestBUSD>(bob, bob_lp_balance, 0, 0);
    //     // expect the small amount will result one of the amount to be zero and unable to remove liquidity
    //     router::remove_liquidity<TestCAKE, TestBUSD>(alice, alice_lp_balance, 0, 0);
    // }

    // #[test(dev = @dev, admin= @admin, resource_account = @evo, treasury = @treasury, bob = @0x12345, alice = @0x12346)]
    // fun test_swap_exact_input(
    //     dev: &signer,
    //     admin: &signer,
    //     resource_account: &signer,
    //     treasury: &signer,
    //     bob: &signer,
    //     alice: &signer,
    // ) {
    //     account::create_account_for_test(signer::address_of(bob));
    //     account::create_account_for_test(signer::address_of(alice));

    //     setup_test_with_genesis(dev, admin, treasury, resource_account);

    //     let coin_owner = test_coins::init_coins();

    //     test_coins::register_and_mint<TestCAKE>(&coin_owner, bob, 100 * pow(10, 8));
    //     test_coins::register_and_mint<TestBUSD>(&coin_owner, bob, 100 * pow(10, 8));
    //     test_coins::register_and_mint<TestCAKE>(&coin_owner, alice, 100 * pow(10, 8));

    //     let initial_reserve_x = 5 * pow(10, 8);
    //     let initial_reserve_y = 10 * pow(10, 8);
    //     let input_x = 2 * pow(10, 8);
    //     // bob provider liquidity for 5:10 CAKE-BUSD
    //     router::add_liquidity<TestCAKE, TestBUSD>(bob, initial_reserve_x, initial_reserve_y, 0, 0);
    //     let bob_suppose_lp_balance = math::sqrt(((initial_reserve_x as u128) * (initial_reserve_y as u128))) - MINIMUM_LIQUIDITY;
    //     let suppose_total_supply = bob_suppose_lp_balance + MINIMUM_LIQUIDITY;

    //     // let bob_lp_balance = coin::balance<LPToken<TestBUSD, TestCAKE>>(signer::address_of(bob));
    //     let alice_token_x_before_balance = coin::balance<TestCAKE>(signer::address_of(alice));

    //     router::swap_exact_input<TestCAKE, TestBUSD>(alice, input_x, 0);

    //     let (treasury_balance_x, treasury_balance_y, team_balance_x, team_balance_y, pool_balance_x, pool_balance_y) = swap::token_fees_accumulated<TestBUSD, TestCAKE>();

    //     assert!(treasury_balance_y == 2 * pow(10, 5), 125);
    //     // assert!(team_balance_y == 4 * pow(10, 6), 126);
    //     // assert!(pool_balance_y == 8 * pow(10, 6), 127);

    //     let alice_token_x_after_balance = coin::balance<TestCAKE>(signer::address_of(alice));
    //     let alice_token_y_after_balance = coin::balance<TestBUSD>(signer::address_of(alice));

    //     let total_fees = swap::token_fees<TestBUSD, TestCAKE>();

    //     let amount_x_in_with_fee = input_x - (((input_x as u128) * 10u128 / 10000u128) as u64);

    //     let output_y = calc_output_using_input(input_x, initial_reserve_x, initial_reserve_y, total_fees);
    //     let new_reserve_x = initial_reserve_x + amount_x_in_with_fee;
    //     let new_reserve_y = initial_reserve_y - (output_y as u64);

    //     let (reserve_y, reserve_x, _) = swap::token_reserves<TestBUSD, TestCAKE>();
    //     assert!((alice_token_x_before_balance - alice_token_x_after_balance) == input_x, 99);
    //     assert!(alice_token_y_after_balance == (output_y as u64), 98);
    //     assert!(reserve_x == new_reserve_x, 97);
    //     assert!(reserve_y == new_reserve_y, 96);

    //     let bob_token_x_before_balance = coin::balance<TestCAKE>(signer::address_of(bob));
    //     let bob_token_y_before_balance = coin::balance<TestBUSD>(signer::address_of(bob));

    //     router::remove_liquidity<TestCAKE, TestBUSD>(bob, (bob_suppose_lp_balance as u64), 0, 0);

    //     let bob_token_x_after_balance = coin::balance<TestCAKE>(signer::address_of(bob));
    //     let bob_token_y_after_balance = coin::balance<TestBUSD>(signer::address_of(bob));

    //     // let suppose_k_last = ((initial_reserve_x * initial_reserve_y) as u128);
    //     // let suppose_k = ((new_reserve_x * new_reserve_y) as u128);
    //     // let suppose_fee_amount = calc_fee_lp(suppose_total_supply, suppose_k, suppose_k_last);
    //     // suppose_total_supply = suppose_total_supply + suppose_fee_amount;

    //     let bob_remove_liquidity_x = ((new_reserve_x) as u128) * bob_suppose_lp_balance / suppose_total_supply;
    //     let bob_remove_liquidity_y = ((new_reserve_y) as u128) * bob_suppose_lp_balance / suppose_total_supply;
    //     new_reserve_x = new_reserve_x - (bob_remove_liquidity_x as u64);
    //     new_reserve_y = new_reserve_y - (bob_remove_liquidity_y as u64);
    //     suppose_total_supply = suppose_total_supply - bob_suppose_lp_balance;

    //     assert!((bob_token_x_after_balance - bob_token_x_before_balance) == (bob_remove_liquidity_x as u64), 95);
    //     assert!((bob_token_y_after_balance - bob_token_y_before_balance) == (bob_remove_liquidity_y as u64), 94);

    //     // swap::withdraw_fee<TestCAKE, TestBUSD>(treasury);
    //     // let treasury_lp_after_balance = coin::balance<LPToken<TestBUSD, TestCAKE>>(signer::address_of(treasury));
    //     // router::remove_liquidity<TestCAKE, TestBUSD>(treasury, (suppose_fee_amount as u64), 0, 0);
    //     // let treasury_token_x_after_balance = coin::balance<TestCAKE>(signer::address_of(treasury));
    //     // let treasury_token_y_after_balance = coin::balance<TestBUSD>(signer::address_of(treasury));

    //     // let treasury_remove_liquidity_x = ((new_reserve_x) as u128) * suppose_fee_amount / suppose_total_supply;
    //     // let treasury_remove_liquidity_y = ((new_reserve_y) as u128) * suppose_fee_amount / suppose_total_supply;

    //     // assert!(treasury_lp_after_balance == (suppose_fee_amount as u64), 93);
    //     // assert!(treasury_token_x_after_balance == (treasury_remove_liquidity_x as u64), 92);
    //     // assert!(treasury_token_y_after_balance == (treasury_remove_liquidity_y as u64), 91);
    // }

    // #[test(dev = @dev, admin= @admin, resource_account = @evo, treasury = @treasury, bob = @0x12345, alice = @0x12346)]
    // fun test_swap_exact_input_overflow(
    //     dev: &signer,
    //     admin: &signer,
    //     resource_account: &signer,
    //     treasury: &signer,
    //     bob: &signer,
    //     alice: &signer,
    // ) {
    //     account::create_account_for_test(signer::address_of(bob));
    //     account::create_account_for_test(signer::address_of(alice));

    //     setup_test_with_genesis(dev, admin, treasury, resource_account);

    //     let coin_owner = test_coins::init_coins();

    //     test_coins::register_and_mint<TestCAKE>(&coin_owner, bob, MAX_U64);
    //     test_coins::register_and_mint<TestBUSD>(&coin_owner, bob, MAX_U64);
    //     test_coins::register_and_mint<TestCAKE>(&coin_owner, alice, MAX_U64);

    //     let initial_reserve_x = MAX_U64 / pow(10, 4);
    //     let initial_reserve_y = MAX_U64 / pow(10, 4);
    //     let input_x = pow(10, 9) * pow(10, 8);
    //     // bob provider liquidity for 5:10 CAKE-BUSD
    //     router::add_liquidity<TestCAKE, TestBUSD>(bob, initial_reserve_x, initial_reserve_y, 0, 0);

    //     router::swap_exact_input<TestCAKE, TestBUSD>(alice, input_x, 0);
    // }

    // #[test(dev = @dev, admin= @admin, resource_account = @evo, treasury = @treasury, bob = @0x12345, alice = @0x12346)]
    // #[expected_failure(abort_code = 65542)]
    // fun test_swap_exact_input_with_not_enough_liquidity(
    //     dev: &signer,
    //     admin: &signer,
    //     resource_account: &signer,
    //     treasury: &signer,
    //     bob: &signer,
    //     alice: &signer,
    // ) {
    //     account::create_account_for_test(signer::address_of(bob));
    //     account::create_account_for_test(signer::address_of(alice));

    //     setup_test_with_genesis(dev, admin, treasury, resource_account);

    //     let coin_owner = test_coins::init_coins();

    //     test_coins::register_and_mint<TestCAKE>(&coin_owner, bob, 1000 * pow(10, 8));
    //     test_coins::register_and_mint<TestBUSD>(&coin_owner, bob, 1000 * pow(10, 8));
    //     test_coins::register_and_mint<TestCAKE>(&coin_owner, alice, 1000 * pow(10, 8));

    //     let initial_reserve_x = 100 * pow(10, 8);
    //     let initial_reserve_y = 200 * pow(10, 8);
    //     let input_x = 10000 * pow(10, 8);
    //     // bob provider liquidity for 5:10 CAKE-BUSD
    //     router::add_liquidity<TestCAKE, TestBUSD>(bob, initial_reserve_x, initial_reserve_y, 0, 0);


    //     router::swap_exact_input<TestCAKE, TestBUSD>(alice, input_x, 0);
    // }

    // #[test(dev = @dev, admin= @admin, resource_account = @evo, treasury = @treasury, bob = @0x12345, alice = @0x12346)]
    // #[expected_failure(abort_code = 0)]
    // fun test_swap_exact_input_under_min_output(
    //     dev: &signer,
    //     admin: &signer,
    //     resource_account: &signer,
    //     treasury: &signer,
    //     bob: &signer,
    //     alice: &signer,
    // ) {
    //     account::create_account_for_test(signer::address_of(bob));
    //     account::create_account_for_test(signer::address_of(alice));

    //     setup_test_with_genesis(dev, admin, treasury, resource_account);

    //     let coin_owner = test_coins::init_coins();

    //     test_coins::register_and_mint<TestCAKE>(&coin_owner, bob, 100 * pow(10, 8));
    //     test_coins::register_and_mint<TestBUSD>(&coin_owner, bob, 100 * pow(10, 8));
    //     test_coins::register_and_mint<TestCAKE>(&coin_owner, alice, 100 * pow(10, 8));

    //     let initial_reserve_x = 5 * pow(10, 8);
    //     let initial_reserve_y = 10 * pow(10, 8);
    //     let input_x = 2 * pow(10, 8);
    //     // bob provider liquidity for 5:10 CAKE-BUSD
    //     router::add_liquidity<TestCAKE, TestBUSD>(bob, initial_reserve_x, initial_reserve_y, 0, 0);

    //     let total_fees = swap::token_fees<TestBUSD, TestCAKE>();

    //     let output_y = calc_output_using_input(input_x, initial_reserve_x, initial_reserve_y, total_fees);
    //     router::swap_exact_input<TestCAKE, TestBUSD>(alice, input_x, ((output_y + 1) as u64));
    // }

    // #[test(dev = @dev, admin= @admin, resource_account = @evo, treasury = @treasury, bob = @0x12345, alice = @0x12346)]
    // fun test_swap_exact_output(
    //     dev: &signer,
    //     admin: &signer,
    //     resource_account: &signer,
    //     treasury: &signer,
    //     bob: &signer,
    //     alice: &signer,
    // ) {
    //     account::create_account_for_test(signer::address_of(bob));
    //     account::create_account_for_test(signer::address_of(alice));

    //     setup_test_with_genesis(dev, admin, treasury, resource_account);

    //     let coin_owner = test_coins::init_coins();

    //     test_coins::register_and_mint<TestCAKE>(&coin_owner, bob, 100 * pow(10, 8));
    //     test_coins::register_and_mint<TestBUSD>(&coin_owner, bob, 100 * pow(10, 8));
    //     test_coins::register_and_mint<TestCAKE>(&coin_owner, alice, 100 * pow(10, 8));

    //     let initial_reserve_x = 5 * pow(10, 8);
    //     let initial_reserve_y = 10 * pow(10, 8);
    //     let output_y = 166319299;
    //     let input_x_max = 15 * pow(10, 7);

    //     // bob provider liquidity for 5:10 CAKE-BUSD
    //     router::add_liquidity<TestCAKE, TestBUSD>(bob, initial_reserve_x, initial_reserve_y, 0, 0);
    //     let bob_suppose_lp_balance = math::sqrt(((initial_reserve_x as u128) * (initial_reserve_y as u128))) - MINIMUM_LIQUIDITY;
    //     let suppose_total_supply = bob_suppose_lp_balance + MINIMUM_LIQUIDITY;

    //     let alice_token_x_before_balance = coin::balance<TestCAKE>(signer::address_of(alice));

    //     router::swap_exact_output<TestCAKE, TestBUSD>(alice, output_y, input_x_max);

    //     let (treasury_balance_x, treasury_balance_y, team_balance_x, team_balance_y, pool_balance_x, pool_balance_y) = swap::token_fees_accumulated<TestBUSD, TestCAKE>();

    //     assert!(treasury_balance_y > 0, 125);
    //     // assert!(team_balance_x == 4 * pow(10, 6), 126);
    //     // assert!(pool_balance_x == 8 * pow(10, 6), 127);

    //     let alice_token_x_after_balance = coin::balance<TestCAKE>(signer::address_of(alice));
    //     let alice_token_y_after_balance = coin::balance<TestBUSD>(signer::address_of(alice));

    //     let total_fees = swap::token_fees<TestBUSD, TestCAKE>();

    //     let input_x = calc_input_using_output(output_y, initial_reserve_x, initial_reserve_y, total_fees);

    //     let amount_x_in_with_fee = input_x - (((input_x as u128) * 610u128 / 10000u128));

    //     let new_reserve_x = initial_reserve_x + (amount_x_in_with_fee as u64);
    //     let new_reserve_y = initial_reserve_y - output_y;

    //     let (reserve_y, reserve_x, _) = swap::token_reserves<TestBUSD, TestCAKE>();
    //     assert!((alice_token_x_before_balance - alice_token_x_after_balance) == (input_x as u64), 99);
    //     assert!(alice_token_y_after_balance == output_y, 98);
    //     assert!(reserve_x * reserve_y >= new_reserve_x * new_reserve_y, 97);
    //     // assert!(reserve_y == new_reserve_y, 96);

    //     let bob_token_x_before_balance = coin::balance<TestCAKE>(signer::address_of(bob));
    //     let bob_token_y_before_balance = coin::balance<TestBUSD>(signer::address_of(bob));

    //     router::remove_liquidity<TestCAKE, TestBUSD>(bob, (bob_suppose_lp_balance as u64), 0, 0);

    //     let bob_token_x_after_balance = coin::balance<TestCAKE>(signer::address_of(bob));
    //     let bob_token_y_after_balance = coin::balance<TestBUSD>(signer::address_of(bob));

    //     // let suppose_k_last = ((initial_reserve_x * initial_reserve_y) as u128);
    //     // let suppose_k = ((new_reserve_x * new_reserve_y) as u128);
    //     // let suppose_fee_amount = calc_fee_lp(suppose_total_supply, suppose_k, suppose_k_last);
    //     // suppose_total_supply = suppose_total_supply + suppose_fee_amount;

    //     let bob_remove_liquidity_x = ((new_reserve_x) as u128) * bob_suppose_lp_balance / suppose_total_supply;
    //     let bob_remove_liquidity_y = ((new_reserve_y) as u128) * bob_suppose_lp_balance / suppose_total_supply;
    //     new_reserve_x = new_reserve_x - (bob_remove_liquidity_x as u64);
    //     new_reserve_y = new_reserve_y - (bob_remove_liquidity_y as u64);
    //     suppose_total_supply = suppose_total_supply - bob_suppose_lp_balance;

    //     // assert!((bob_token_x_after_balance - bob_token_x_before_balance) == (bob_remove_liquidity_x as u64), 95);
    //     // assert!((bob_token_y_after_balance - bob_token_y_before_balance) == (bob_remove_liquidity_y as u64), 94);

    //     // swap::withdraw_fee<TestCAKE, TestBUSD>(treasury);
    //     // let treasury_lp_after_balance = coin::balance<LPToken<TestBUSD, TestCAKE>>(signer::address_of(treasury));
    //     // router::remove_liquidity<TestCAKE, TestBUSD>(treasury, (suppose_fee_amount as u64), 0, 0);
    //     // let treasury_token_x_after_balance = coin::balance<TestCAKE>(signer::address_of(treasury));
    //     // let treasury_token_y_after_balance = coin::balance<TestBUSD>(signer::address_of(treasury));

    //     // let treasury_remove_liquidity_x = ((new_reserve_x) as u128) * suppose_fee_amount / suppose_total_supply;
    //     // let treasury_remove_liquidity_y = ((new_reserve_y) as u128) * suppose_fee_amount / suppose_total_supply;

    //     // assert!(treasury_lp_after_balance == (suppose_fee_amount as u64), 93);
    //     // assert!(treasury_token_x_after_balance == (treasury_remove_liquidity_x as u64), 92);
    //     // assert!(treasury_token_y_after_balance == (treasury_remove_liquidity_y as u64), 91);
    // }

    // #[test(dev = @dev, admin= @admin, resource_account = @evo, treasury = @treasury, bob = @0x12345, alice = @0x12346)]
    // #[expected_failure]
    // fun test_swap_exact_output_with_not_enough_liquidity(
    //     dev: &signer,
    //     admin: &signer,
    //     resource_account: &signer,
    //     treasury: &signer,
    //     bob: &signer,
    //     alice: &signer,
    // ) {
    //     account::create_account_for_test(signer::address_of(bob));
    //     account::create_account_for_test(signer::address_of(alice));

    //     setup_test_with_genesis(dev, admin, treasury, resource_account);

    //     let coin_owner = test_coins::init_coins();

    //     test_coins::register_and_mint<TestCAKE>(&coin_owner, bob, 1000 * pow(10, 8));
    //     test_coins::register_and_mint<TestBUSD>(&coin_owner, bob, 1000 * pow(10, 8));
    //     test_coins::register_and_mint<TestCAKE>(&coin_owner, alice, 1000 * pow(10, 8));

    //     let initial_reserve_x = 100 * pow(10, 8);
    //     let initial_reserve_y = 200 * pow(10, 8);
    //     let output_y = 1000 * pow(10, 8);
    //     let input_x_max = 1000 * pow(10, 8);

    //     // bob provider liquidity for 5:10 CAKE-BUSD
    //     router::add_liquidity<TestCAKE, TestBUSD>(bob, initial_reserve_x, initial_reserve_y, 0, 0);

    //     router::swap_exact_output<TestCAKE, TestBUSD>(alice, output_y, input_x_max);
    // }

    // #[test(dev = @dev, admin= @admin, resource_account = @evo, treasury = @treasury, bob = @0x12345, alice = @0x12346)]
    // #[expected_failure(abort_code = 1)]
    // fun test_swap_exact_output_excceed_max_input(
    //     dev: &signer,
    //     admin: &signer,
    //     resource_account: &signer,
    //     treasury: &signer,
    //     bob: &signer,
    //     alice: &signer,
    // ) {
    //     account::create_account_for_test(signer::address_of(bob));
    //     account::create_account_for_test(signer::address_of(alice));

    //     setup_test_with_genesis(dev, admin, treasury, resource_account);

    //     let coin_owner = test_coins::init_coins();

    //     test_coins::register_and_mint<TestCAKE>(&coin_owner, bob, 1000 * pow(10, 8));
    //     test_coins::register_and_mint<TestBUSD>(&coin_owner, bob, 1000 * pow(10, 8));
    //     test_coins::register_and_mint<TestCAKE>(&coin_owner, alice, 1000 * pow(10, 8));

    //     let initial_reserve_x = 50 * pow(10, 8);
    //     let initial_reserve_y = 100 * pow(10, 8);
    //     let output_y = 166319299;

    //     // bob provider liquidity for 5:10 CAKE-BUSD
    //     router::add_liquidity<TestCAKE, TestBUSD>(bob, initial_reserve_x, initial_reserve_y, 0, 0);

    //     let total_fees = swap::token_fees<TestBUSD, TestCAKE>();

    //     let input_x = calc_input_using_output(output_y, initial_reserve_x, initial_reserve_y, total_fees);
    //     router::swap_exact_output<TestCAKE, TestBUSD>(alice, output_y, ((input_x - 1) as u64));
    // }

    // #[test(dev = @dev, admin= @admin, resource_account = @evo, treasury = @treasury, bob = @0x12345, alice = @0x12346)]
    // fun test_swap_x_to_exact_y_direct_external(
    //     dev: &signer,
    //     admin: &signer,
    //     resource_account: &signer,
    //     treasury: &signer,
    //     bob: &signer,
    //     alice: &signer,
    // ) {
    //     account::create_account_for_test(signer::address_of(bob));
    //     account::create_account_for_test(signer::address_of(alice));

    //     setup_test_with_genesis(dev, admin, treasury, resource_account);

    //     let coin_owner = test_coins::init_coins();

    //     test_coins::register_and_mint<TestCAKE>(&coin_owner, bob, 100 * pow(10, 8));
    //     test_coins::register_and_mint<TestBUSD>(&coin_owner, bob, 100 * pow(10, 8));
    //     test_coins::register_and_mint<TestCAKE>(&coin_owner, alice, 100 * pow(10, 8));

    //     let initial_reserve_x = 5 * pow(10, 8);
    //     let initial_reserve_y = 10 * pow(10, 8);
    //     let output_y = 166319299;
    //     // let input_x_max = 1 * pow(10, 8);

    //     // bob provider liquidity for 5:10 CAKE-BUSD
    //     router::add_liquidity<TestCAKE, TestBUSD>(bob, initial_reserve_x, initial_reserve_y, 0, 0);
    //     let bob_suppose_lp_balance = math::sqrt(((initial_reserve_x as u128) * (initial_reserve_y as u128))) - MINIMUM_LIQUIDITY;
    //     let suppose_total_supply = bob_suppose_lp_balance + MINIMUM_LIQUIDITY;

    //     let alice_addr = signer::address_of(alice);

    //     let alice_token_x_before_balance = coin::balance<TestCAKE>(alice_addr);

    //     let total_fees = swap::token_fees<TestBUSD, TestCAKE>();

    //     let input_x = calc_input_using_output(output_y, initial_reserve_x, initial_reserve_y, total_fees); 

    //     let x_in_amount = router::get_amount_in<TestCAKE, TestBUSD>(output_y);
    //     assert!(x_in_amount == (input_x as u64), 102);

    //     let input_x_coin = coin::withdraw(alice, (input_x as u64));

    //     let (x_out, y_out) =  router::swap_x_to_exact_y_direct_external<TestCAKE, TestBUSD>(input_x_coin, output_y);

    //     assert!(coin::value(&x_out) == 0, 101);
    //     assert!(coin::value(&y_out) == output_y, 100);
    //     coin::register<TestBUSD>(alice);
    //     coin::deposit<TestCAKE>(alice_addr, x_out);
    //     coin::deposit<TestBUSD>(alice_addr, y_out);

    //     let alice_token_x_after_balance = coin::balance<TestCAKE>(alice_addr);
    //     let alice_token_y_after_balance = coin::balance<TestBUSD>(alice_addr);

    //     let new_reserve_x = initial_reserve_x + (input_x as u64);
    //     let new_reserve_y = initial_reserve_y - output_y;

    //     let (reserve_y, reserve_x, _) = swap::token_reserves<TestBUSD, TestCAKE>();
    //     assert!((alice_token_x_before_balance - alice_token_x_after_balance) == (input_x as u64), 99);
    //     assert!(alice_token_y_after_balance == output_y, 98);
    //     // assert!(reserve_x * reserve_y >= new_reserve_x * new_reserve_y, 97);

    //     let bob_token_x_before_balance = coin::balance<TestCAKE>(signer::address_of(bob));
    //     let bob_token_y_before_balance = coin::balance<TestBUSD>(signer::address_of(bob));

    //     router::remove_liquidity<TestCAKE, TestBUSD>(bob, (bob_suppose_lp_balance as u64), 0, 0);

    //     let bob_token_x_after_balance = coin::balance<TestCAKE>(signer::address_of(bob));
    //     let bob_token_y_after_balance = coin::balance<TestBUSD>(signer::address_of(bob));

    //     // let suppose_k_last = ((initial_reserve_x * initial_reserve_y) as u128);
    //     // let suppose_k = ((new_reserve_x * new_reserve_y) as u128);
    //     // let suppose_fee_amount = calc_fee_lp(suppose_total_supply, suppose_k, suppose_k_last);
    //     // suppose_total_supply = suppose_total_supply + suppose_fee_amount;

    //     let bob_remove_liquidity_x = ((new_reserve_x) as u128) * bob_suppose_lp_balance / suppose_total_supply;
    //     let bob_remove_liquidity_y = ((new_reserve_y) as u128) * bob_suppose_lp_balance / suppose_total_supply;
    //     new_reserve_x = new_reserve_x - (bob_remove_liquidity_x as u64);
    //     new_reserve_y = new_reserve_y - (bob_remove_liquidity_y as u64);
    //     suppose_total_supply = suppose_total_supply - bob_suppose_lp_balance;

    //     // assert!((bob_token_x_after_balance - bob_token_x_before_balance) == (bob_remove_liquidity_x as u64), 95);
    //     // assert!((bob_token_y_after_balance - bob_token_y_before_balance) == (bob_remove_liquidity_y as u64), 94);

    //     // swap::withdraw_fee<TestCAKE, TestBUSD>(treasury);
    //     // let treasury_lp_after_balance = coin::balance<LPToken<TestBUSD, TestCAKE>>(signer::address_of(treasury));
    //     // router::remove_liquidity<TestCAKE, TestBUSD>(treasury, (suppose_fee_amount as u64), 0, 0);
    //     // let treasury_token_x_after_balance = coin::balance<TestCAKE>(signer::address_of(treasury));
    //     // let treasury_token_y_after_balance = coin::balance<TestBUSD>(signer::address_of(treasury));

    //     // let treasury_remove_liquidity_x = ((new_reserve_x) as u128) * suppose_fee_amount / suppose_total_supply;
    //     // let treasury_remove_liquidity_y = ((new_reserve_y) as u128) * suppose_fee_amount / suppose_total_supply;

    //     // assert!(treasury_lp_after_balance == (suppose_fee_amount as u64), 93);
    //     // assert!(treasury_token_x_after_balance == (treasury_remove_liquidity_x as u64), 92);
    //     // assert!(treasury_token_y_after_balance == (treasury_remove_liquidity_y as u64), 91);
    // }

    // #[test(dev = @dev, admin= @admin, resource_account = @evo, treasury = @treasury, bob = @0x12345, alice = @0x12346)]
    // fun test_swap_x_to_exact_y_direct_external_with_more_x_in(
    //     dev: &signer,
    //     admin: &signer,
    //     resource_account: &signer,
    //     treasury: &signer,
    //     bob: &signer,
    //     alice: &signer,
    // ) {
    //     account::create_account_for_test(signer::address_of(bob));
    //     account::create_account_for_test(signer::address_of(alice));

    //     setup_test_with_genesis(dev, admin, treasury, resource_account);

    //     let coin_owner = test_coins::init_coins();

    //     test_coins::register_and_mint<TestCAKE>(&coin_owner, bob, 100 * pow(10, 8));
    //     test_coins::register_and_mint<TestBUSD>(&coin_owner, bob, 100 * pow(10, 8));
    //     test_coins::register_and_mint<TestCAKE>(&coin_owner, alice, 100 * pow(10, 8));

    //     let initial_reserve_x = 5 * pow(10, 8);
    //     let initial_reserve_y = 10 * pow(10, 8);
    //     let output_y = 166319299;
    //     // let input_x_max = 1 * pow(10, 8);

    //     // bob provider liquidity for 5:10 CAKE-BUSD
    //     router::add_liquidity<TestCAKE, TestBUSD>(bob, initial_reserve_x, initial_reserve_y, 0, 0);
    //     let bob_suppose_lp_balance = math::sqrt(((initial_reserve_x as u128) * (initial_reserve_y as u128))) - MINIMUM_LIQUIDITY;
    //     let suppose_total_supply = bob_suppose_lp_balance + MINIMUM_LIQUIDITY;

    //     let alice_addr = signer::address_of(alice);

    //     let alice_token_x_before_balance = coin::balance<TestCAKE>(alice_addr);

    //     let total_fees = swap::token_fees<TestBUSD, TestCAKE>();

    //     let input_x = calc_input_using_output(output_y, initial_reserve_x, initial_reserve_y, total_fees); 

    //     let x_in_more = 666666;

    //     let input_x_coin = coin::withdraw(alice, (input_x as u64) + x_in_more);

    //     let (x_out, y_out) =  router::swap_x_to_exact_y_direct_external<TestCAKE, TestBUSD>(input_x_coin, output_y);

    //     assert!(coin::value(&x_out) == x_in_more, 101);
    //     assert!(coin::value(&y_out) == output_y, 100);
    //     coin::register<TestBUSD>(alice);
    //     coin::deposit<TestCAKE>(alice_addr, x_out);
    //     coin::deposit<TestBUSD>(alice_addr, y_out);

    //     let alice_token_x_after_balance = coin::balance<TestCAKE>(alice_addr);
    //     let alice_token_y_after_balance = coin::balance<TestBUSD>(alice_addr);

    //     let new_reserve_x = initial_reserve_x + (input_x as u64);
    //     let new_reserve_y = initial_reserve_y - output_y;

    //     let (reserve_y, reserve_x, _) = swap::token_reserves<TestBUSD, TestCAKE>();
    //     assert!((alice_token_x_before_balance - alice_token_x_after_balance) == (input_x as u64), 99);
    //     assert!(alice_token_y_after_balance == output_y, 98);
    //     // assert!(reserve_x * reserve_y >= new_reserve_x * new_reserve_y, 97);

    //     let bob_token_x_before_balance = coin::balance<TestCAKE>(signer::address_of(bob));
    //     let bob_token_y_before_balance = coin::balance<TestBUSD>(signer::address_of(bob));

    //     router::remove_liquidity<TestCAKE, TestBUSD>(bob, (bob_suppose_lp_balance as u64), 0, 0);

    //     let bob_token_x_after_balance = coin::balance<TestCAKE>(signer::address_of(bob));
    //     let bob_token_y_after_balance = coin::balance<TestBUSD>(signer::address_of(bob));

    //     // let suppose_k_last = ((initial_reserve_x * initial_reserve_y) as u128);
    //     // let suppose_k = ((new_reserve_x * new_reserve_y) as u128);
    //     // let suppose_fee_amount = calc_fee_lp(suppose_total_supply, suppose_k, suppose_k_last);
    //     // suppose_total_supply = suppose_total_supply + suppose_fee_amount;

    //     let bob_remove_liquidity_x = ((new_reserve_x) as u128) * bob_suppose_lp_balance / suppose_total_supply;
    //     let bob_remove_liquidity_y = ((new_reserve_y) as u128) * bob_suppose_lp_balance / suppose_total_supply;
    //     new_reserve_x = new_reserve_x - (bob_remove_liquidity_x as u64);
    //     new_reserve_y = new_reserve_y - (bob_remove_liquidity_y as u64);
    //     suppose_total_supply = suppose_total_supply - bob_suppose_lp_balance;

    //     // assert!((bob_token_x_after_balance - bob_token_x_before_balance) == (bob_remove_liquidity_x as u64), 95);
    //     // assert!((bob_token_y_after_balance - bob_token_y_before_balance) == (bob_remove_liquidity_y as u64), 94);

    //     // swap::withdraw_fee<TestCAKE, TestBUSD>(treasury);
    //     // let treasury_lp_after_balance = coin::balance<LPToken<TestBUSD, TestCAKE>>(signer::address_of(treasury));
    //     // router::remove_liquidity<TestCAKE, TestBUSD>(treasury, (suppose_fee_amount as u64), 0, 0);
    //     // let treasury_token_x_after_balance = coin::balance<TestCAKE>(signer::address_of(treasury));
    //     // let treasury_token_y_after_balance = coin::balance<TestBUSD>(signer::address_of(treasury));

    //     // let treasury_remove_liquidity_x = ((new_reserve_x) as u128) * suppose_fee_amount / suppose_total_supply;
    //     // let treasury_remove_liquidity_y = ((new_reserve_y) as u128) * suppose_fee_amount / suppose_total_supply;

    //     // assert!(treasury_lp_after_balance == (suppose_fee_amount as u64), 93);
    //     // assert!(treasury_token_x_after_balance == (treasury_remove_liquidity_x as u64), 92);
    //     // assert!(treasury_token_y_after_balance == (treasury_remove_liquidity_y as u64), 91);
    // }

    // #[test(dev = @dev, admin= @admin, resource_account = @evo, treasury = @treasury, bob = @0x12345, alice = @0x12346)]
    // #[expected_failure(abort_code = 2)]
    // fun test_swap_x_to_exact_y_direct_external_with_less_x_in(
    //     dev: &signer,
    //     admin: &signer,
    //     resource_account: &signer,
    //     treasury: &signer,
    //     bob: &signer,
    //     alice: &signer,
    // ) {
    //     account::create_account_for_test(signer::address_of(bob));
    //     account::create_account_for_test(signer::address_of(alice));

    //     setup_test_with_genesis(dev, admin, treasury, resource_account);

    //     let coin_owner = test_coins::init_coins();

    //     test_coins::register_and_mint<TestCAKE>(&coin_owner, bob, 100 * pow(10, 8));
    //     test_coins::register_and_mint<TestBUSD>(&coin_owner, bob, 100 * pow(10, 8));
    //     test_coins::register_and_mint<TestCAKE>(&coin_owner, alice, 100 * pow(10, 8));

    //     let initial_reserve_x = 5 * pow(10, 8);
    //     let initial_reserve_y = 10 * pow(10, 8);
    //     let output_y = 166319299;
    //     // let input_x_max = 1 * pow(10, 8);

    //     // bob provider liquidity for 5:10 CAKE-BUSD
    //     router::add_liquidity<TestCAKE, TestBUSD>(bob, initial_reserve_x, initial_reserve_y, 0, 0);

    //     let alice_addr = signer::address_of(alice);

    //     let total_fees = swap::token_fees<TestBUSD, TestCAKE>();

    //     let input_x = calc_input_using_output(output_y, initial_reserve_x, initial_reserve_y, total_fees); 

    //     let x_in_less = 66;

    //     let input_x_coin = coin::withdraw(alice, (input_x as u64) - x_in_less);

    //     let (x_out, y_out) =  router::swap_x_to_exact_y_direct_external<TestCAKE, TestBUSD>(input_x_coin, output_y);

    //     coin::register<TestBUSD>(alice);
    //     coin::deposit<TestCAKE>(alice_addr, x_out);
    //     coin::deposit<TestBUSD>(alice_addr, y_out);
    // }

    // #[test(dev = @dev, admin= @admin, resource_account = @evo, treasury = @treasury, bob = @0x12345, alice = @0x12346)]
    // fun test_get_amount_in(
    //     dev: &signer,
    //     admin: &signer,
    //     resource_account: &signer,
    //     treasury: &signer,
    //     bob: &signer,
    //     alice: &signer,
    // ) {
    //     account::create_account_for_test(signer::address_of(bob));
    //     account::create_account_for_test(signer::address_of(alice));

    //     setup_test_with_genesis(dev, admin, treasury, resource_account);

    //     let coin_owner = test_coins::init_coins();

    //     test_coins::register_and_mint<TestCAKE>(&coin_owner, bob, 100 * pow(10, 8));
    //     test_coins::register_and_mint<TestBUSD>(&coin_owner, bob, 100 * pow(10, 8));
    //     test_coins::register_and_mint<TestCAKE>(&coin_owner, alice, 100 * pow(10, 8));

    //     let initial_reserve_x = 5 * pow(10, 8);
    //     let initial_reserve_y = 10 * pow(10, 8);
    //     let output_y = 166319299;
    //     let output_x = 166319299;
    //     // let input_x_max = 1 * pow(10, 8);

    //     // bob provider liquidity for 5:10 CAKE-BUSD
    //     router::add_liquidity<TestCAKE, TestBUSD>(bob, initial_reserve_x, initial_reserve_y, 0, 0);

    //     let total_fees = swap::token_fees<TestBUSD, TestCAKE>();

    //     let input_x = calc_input_using_output(output_y, initial_reserve_x, initial_reserve_y, total_fees); 

    //     let x_in_amount = router::get_amount_in<TestCAKE, TestBUSD>(output_y);
    //     assert!(x_in_amount == (input_x as u64), 102);

    //     let input_y = calc_input_using_output(output_x, initial_reserve_y, initial_reserve_x, total_fees); 

    //     let y_in_amount = router::get_amount_in<TestBUSD, TestCAKE>(output_x);
    //     assert!(y_in_amount == (input_y as u64), 101);
    // }


    // public fun get_token_reserves<X, Y>(): (u64, u64) {

    //     let is_x_to_y = swap_utils::sort_token_type<X, Y>();
    //     let reserve_x;
    //     let reserve_y;
    //     if(is_x_to_y){
    //         (reserve_x, reserve_y, _) = swap::token_reserves<X, Y>();
    //     }else{
    //         (reserve_y, reserve_x, _) = swap::token_reserves<Y, X>();
    //     };
    //     (reserve_x, reserve_y)

    // }

    // public fun calc_output_using_input(
    //     input_x: u64,
    //     reserve_x: u64,
    //     reserve_y: u64,
    //     total_fees: u128
    // ): u128 {
    //     let fee_denominator = 10000u128 - 20u128 - total_fees;

    //     ((input_x as u128) * fee_denominator * (reserve_y as u128)) / (((reserve_x as u128) * 10000u128) + ((input_x as u128) * fee_denominator))
    // }

    // public fun calc_input_using_output(
    //     output_y: u64,
    //     reserve_x: u64,
    //     reserve_y: u64,
    //     total_fees: u128
    // ): u128 {
    //     let fee_denominator = 10000u128 - 20u128 - total_fees;

    //     ((output_y as u128) * 10000u128 * (reserve_x as u128)) / (fee_denominator * ((reserve_y as u128) - (output_y as u128))) + 1u128
    // }

    // public fun calc_fee_lp(
    //     total_lp_supply: u128,
    //     k: u128,
    //     k_last: u128,
    // ): u128 {
    //     let root_k = math::sqrt(k);
    //     let root_k_last = math::sqrt(k_last);

    //     let numerator = total_lp_supply * (root_k - root_k_last) * 8u128;
    //     let denominator = root_k_last * 17u128 + (root_k * 8u128);
    //     let liquidity = numerator / denominator;
    //     liquidity
    // }
}