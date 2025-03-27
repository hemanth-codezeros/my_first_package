module hem_acc::whitelist_deposit {
    use std::signer;
    use std::vector;
    // use std::debug;
    // use std::string;
    use aptos_framework::account;
    use aptos_framework::coin;
    use aptos_framework::aptos_coin::AptosCoin;

    /// The account doesn't have sufficient balance
    const INSUFFICIENT_BALANCE: u64 = 1001;

    /// This action can only be made by Admin
    const ADMIN_ONLY_ACTION: u64 = 1002;

    /// The address is not whitelisted
    const NOT_WHITELISTED: u64 = 1003;

    /// The address doesn't exist in whitelisted addresses
    const NOT_PRESENT_IN_WHITELISTED: u64 = 1004;

    /// User doesn't have an fund allocated
    const NO_FUND_ALLOCATED: u64 = 1005;

    const SEED_FOR_RESOURCE_ACCOUNT: vector<u8> = b"fund_storage";

    // Resource to store whitelisted addresses
    struct Whitelist has key {
        addresses: vector<address> // only whitelisted addresses
    }

    // Resource to store funds in the resource account
    struct FundStorage has key {
        user_funds: vector<UserFund<AptosCoin>>
    }

    // Fund for each user
    struct UserFund<phantom CoinType> has store {
        balance: coin::Coin<CoinType>,
        address: address
    }

    // Event for logging whitelist modifications
    #[event]
    struct WhitelistEvent has drop, store {
        address: address,
        added: bool // true if added, false if removed
    }

    // Event for logging deposits
    #[event]
    struct DepositEvent has drop, store {
        depositor: address,
        amount: u64
    }

    // Event for logging withdrawl
    #[event]
    struct WithdrawEvent has drop, store {
        withdraw_address: address,
        amount: u64
    }

    // Initializing the contract
    fun init_module(admin: &signer) {
        // Creating a resource account for storing funds
        let (resource_signer, _resource_signer_cap) =
            account::create_resource_account(admin, SEED_FOR_RESOURCE_ACCOUNT);

        let fund_storage = FundStorage {
            user_funds: vector::empty<UserFund<AptosCoin>>()
        };
        move_to(&resource_signer, fund_storage);

        // Initialize the whitelist
        let whitelist = Whitelist {
            addresses: vector::empty<address>()
        };
        move_to(admin, whitelist);
    }

    // Add an address to the whitelist (admin-only)
    public entry fun add_to_whitelist(admin: &signer, address: address) acquires Whitelist {
        assert!(signer::address_of(admin) == @hem_acc, ADMIN_ONLY_ACTION);
        let whitelist = borrow_global_mut<Whitelist>(@hem_acc);
        vector::push_back(&mut whitelist.addresses, address);
        let event = WhitelistEvent { address, added: true };
        0x1::event::emit(event);
    }

    // Remove an address from the whitelist (admin-only)
    public entry fun remove_from_whitelist(
        admin: &signer, address: address
    ) acquires Whitelist {
        assert!(signer::address_of(admin) == @hem_acc, ADMIN_ONLY_ACTION);
        let whitelist = borrow_global_mut<Whitelist>(@hem_acc);
        let (exists, index) = vector::index_of(&whitelist.addresses, &address);
        assert!(exists, NOT_PRESENT_IN_WHITELISTED);
        vector::remove(&mut whitelist.addresses, index);
        let event = WhitelistEvent { address, added: false };
        0x1::event::emit(event);
    }

    // Bulk add addresses to the whitelist (admin-only)
    public entry fun bulk_add_to_whitelist(
        admin: &signer, addresses: vector<address>
    ) acquires Whitelist {
        assert!(signer::address_of(admin) == @hem_acc, ADMIN_ONLY_ACTION);
        let whitelist = borrow_global_mut<Whitelist>(@hem_acc);

        vector::for_each(
            addresses,
            |e| {
                vector::push_back(&mut whitelist.addresses, e);
                let event = WhitelistEvent { address: e, added: true };
                0x1::event::emit(event);
            }
        );
    }

    // Bulk remove addresses from the whitelist (admin-only)
    public entry fun bulk_remove_from_whitelist(
        admin: &signer, addresses: vector<address>
    ) acquires Whitelist {
        assert!(signer::address_of(admin) == @hem_acc, ADMIN_ONLY_ACTION);
        let whitelist = borrow_global_mut<Whitelist>(@hem_acc);

        vector::for_each(
            addresses,
            |e| {
                let (exists, index) = vector::index_of(&whitelist.addresses, &e);
                assert!(exists, NOT_PRESENT_IN_WHITELISTED);
                vector::remove(&mut whitelist.addresses, index);
                let event = WhitelistEvent { address: e, added: false };
                0x1::event::emit(event);
            }
        );
    }

    // Helper function to find index of an address of a user
    fun find_user_fund_index(
        user_funds: &vector<UserFund<AptosCoin>>, user_addr: address
    ): u64 {
        let i = 0;
        let len = vector::length(user_funds);

        // vector::enumerate_ref(
        //     user_funds,
        //     |i, e| {
        //         if (e.address == user_addr) {
        //             return i
        //         };
        //     }
        // );

        while (i < len) {
            let user_fund = vector::borrow(user_funds, i);
            if (user_fund.address == user_addr) {
                return i
            };
            i = i + 1;
        };

        len
    }

    // Transact logic to deposit funds from resource account for whitlisted accounts
    // Deposit funds (only for whitelisted addresses)
    public entry fun deposit(depositor: &signer, amount: u64) acquires Whitelist, FundStorage {
        let depositor_address = signer::address_of(depositor);
        let whitelist = borrow_global<Whitelist>(@hem_acc);
        assert!(
            vector::contains(&whitelist.addresses, &depositor_address),
            NOT_WHITELISTED
        );

        let fund_storage = borrow_global_mut<FundStorage>(get_fund_resource_account());
        let coins_to_deposit = coin::withdraw<AptosCoin>(depositor, amount);

        let index = find_user_fund_index(&fund_storage.user_funds, depositor_address);

        if (index == vector::length(&fund_storage.user_funds)) {
            // User doesn't have an existing fund, create one
            vector::push_back(
                &mut fund_storage.user_funds,
                UserFund<AptosCoin> {
                    balance: coins_to_deposit,
                    address: depositor_address
                }
            );
        } else {
            // User has existing fund, add to it
            let user_fund = vector::borrow_mut(&mut fund_storage.user_funds, index);
            coin::merge(&mut user_fund.balance, coins_to_deposit);
        };

        let event = DepositEvent { depositor: depositor_address, amount };
        0x1::event::emit(event);

    }

    fun get_fund_resource_account(): address {
        account::create_resource_address(&@hem_acc, SEED_FOR_RESOURCE_ACCOUNT)
    }

    // Withdraw funds (admin-only)
    public entry fun withdraw(
        admin: &signer, withdraw_amount: u64, withdraw_address: address
    ) acquires FundStorage {
        assert!(signer::address_of(admin) == @hem_acc, ADMIN_ONLY_ACTION);

        let fund_storage = borrow_global_mut<FundStorage>(get_fund_resource_account());
        let index = find_user_fund_index(&fund_storage.user_funds, withdraw_address);

        // Check if user has existing fund, or else send an error as no funds present
        assert!(index < vector::length(&fund_storage.user_funds), NO_FUND_ALLOCATED);
        let user_fund = vector::borrow_mut(&mut fund_storage.user_funds, index);
        let coins_to_withdraw = coin::extract(&mut user_fund.balance, withdraw_amount);

        // Transfer to user
        coin::deposit(withdraw_address, coins_to_withdraw);

        let event =
            WithdrawEvent { withdraw_address: withdraw_address, amount: withdraw_amount };
        0x1::event::emit(event);

    }

    // Function to transfer funds from withdraw_address to despositor_address
    public entry fun transfer_funds(
        admin: &signer,
        withdraw_address: address,
        depositor_address: address,
        amount: u64
    ) acquires FundStorage {
        assert!(signer::address_of(admin) == @hem_acc, ADMIN_ONLY_ACTION);

        let fund_storage = borrow_global_mut<FundStorage>(get_fund_resource_account());

        let withdrawindex =
            find_user_fund_index(&fund_storage.user_funds, withdraw_address);
        let depositindex =
            find_user_fund_index(&fund_storage.user_funds, depositor_address);

        let element = vector::borrow_mut(&mut fund_storage.user_funds, withdrawindex);
        assert!(coin::value(&element.balance) >= amount, INSUFFICIENT_BALANCE);
        let coins = coin::extract(&mut element.balance, amount);
        let event = WithdrawEvent { withdraw_address: withdraw_address, amount };
        0x1::event::emit(event);

        if (depositindex == vector::length(&fund_storage.user_funds)) {
            // Even though account is whitelisted, its coin account hasn't been initiated.
            vector::push_back(
                &mut fund_storage.user_funds,
                UserFund<AptosCoin> { balance: coins, address: depositor_address }
            );
        } else {
            let deposit_element = vector::borrow_mut(
                &mut fund_storage.user_funds, depositindex
            );
            coin::merge(&mut deposit_element.balance, coins);
        };

        let eventx = DepositEvent { depositor: depositor_address, amount };
        0x1::event::emit(eventx);
    }

    // View function to check if an address is whitelisted
    #[view]
    public fun is_whitelisted(address: address): bool acquires Whitelist {
        let whitelist = borrow_global<Whitelist>(@hem_acc);
        vector::contains(&whitelist.addresses, &address)
    }

    // View function to get the current balance
    #[view]
    public fun get_balance(address: address): u64 acquires FundStorage {

        let fund_storage = borrow_global_mut<FundStorage>(get_fund_resource_account());
        let i: u64 = 0;
        let length = vector::length(&fund_storage.user_funds);
        let result: u64 = 0;

        while (i < length) {
            let element = vector::borrow(&fund_storage.user_funds, i);
            if (address == element.address) {
                result = coin::value(&element.balance);
                break;
            };
            i = i + 1;
        };
        result
    }

    #[test(arg = @hem_acc)]
    fun add_addresses_to_whitelist(arg: signer) acquires Whitelist {
        init_module(&arg);
        let custom_address: address =
            @0xb1f4c9f2d642d40de852b1bd68138143b95dfe8f8f3676adc7b8fd6f81a14441;
        add_to_whitelist(&arg, custom_address);
        assert!(is_whitelisted(custom_address), 1);
    }

    #[test(arg = @hem_acc)]
    fun remove_address_from_whitelist(arg: signer) acquires Whitelist {
        init_module(&arg);
        let custom_address: address =
            @0xb1f4c9f2d642d40de852b1bd68138143b95dfe8f8f3676adc7b8fd6f81a14441;
        add_to_whitelist(&arg, custom_address);
        remove_from_whitelist(&arg, custom_address);
        assert!(!is_whitelisted(custom_address), 1);

    }

    #[test(arg = @hem_acc)]
    fun bulk_adding_and_removing_addresses(arg: signer) acquires Whitelist {
        init_module(&arg);
        let random_address1 = @0x1234567890ABCDEF;
        let random_address2 = @0x9876543210FEDCBA;
        let random_address3 = @0x98765430;
        let random_address4 = @0x9876543;
        let vec = vector::empty<address>();
        vector::push_back(&mut vec, random_address1);
        vector::push_back(&mut vec, random_address2);
        vector::push_back(&mut vec, random_address3);
        vector::push_back(&mut vec, random_address4);

        bulk_add_to_whitelist(&arg, copy vec);
        vector::pop_back(&mut vec);
        vector::pop_back(&mut vec);

        // let utf8_message = string::utf8(b"After popping back addresses");

        bulk_remove_from_whitelist(&arg, vec);
        assert!(!is_whitelisted(random_address1), 1);
        assert!(!is_whitelisted(random_address2), 1);

    }

    #[test(arg = @hem_acc, framework = @aptos_framework)]
    fun deposit_fund(arg: signer, framework: signer) acquires Whitelist, FundStorage {
        init_module(&arg);
        let random_address1 = @0x1234567890ABCDEF;
        let random_address2 = @0x9876543210FEDCBA;
        let random_address3 = @hem_acc;

        let vec = vector::empty<address>();
        vector::push_back(&mut vec, random_address1);
        vector::push_back(&mut vec, random_address2);
        vector::push_back(&mut vec, random_address3);
        bulk_add_to_whitelist(&arg, copy vec);

        assert!(is_whitelisted(random_address1), 1);
        assert!(is_whitelisted(random_address2), 1);
        assert!(is_whitelisted(random_address3), 1);

        let (burn, mint) = aptos_framework::aptos_coin::initialize_for_test(&framework);
        let coin = coin::mint<AptosCoin>(1000000000, &mint);
        account::create_account_for_test(signer::address_of(&arg));
        coin::register<AptosCoin>(&arg);
        coin::deposit(signer::address_of(&arg), coin);

        deposit(&arg, 100);

        coin::destroy_burn_cap(burn);
        coin::destroy_mint_cap(mint);
    }

    #[test(arg = @hem_acc, framework = @aptos_framework)]
    fun withdraw_fund(arg: signer, framework: signer) acquires Whitelist, FundStorage {
        init_module(&arg);
        let random_address2 = @0x9876543210FEDCBA;
        let random_address3 = @hem_acc;

        let vec = vector::empty<address>();
        vector::push_back(&mut vec, random_address2);
        vector::push_back(&mut vec, random_address3);
        bulk_add_to_whitelist(&arg, copy vec);

        assert!(is_whitelisted(random_address2), 1);
        assert!(is_whitelisted(random_address3), 1);

        let (burn, mint) = aptos_framework::aptos_coin::initialize_for_test(&framework);
        let coin = coin::mint<AptosCoin>(1000000000, &mint);
        account::create_account_for_test(signer::address_of(&arg));
        coin::register<AptosCoin>(&arg);
        coin::deposit(signer::address_of(&arg), coin);

        deposit(&arg, 100);

        withdraw(&arg, 25, @hem_acc);
        // Removing 25 out of 100 deposited

        // debug::print( &get_balance(@hem_acc));
        assert!(get_balance(@hem_acc) == 75, 1);

        coin::destroy_burn_cap(burn);
        coin::destroy_mint_cap(mint);
    }

    #[test(arg = @hem_acc, framework = @aptos_framework)]
    fun transfer_fund(arg: signer, framework: signer) acquires Whitelist, FundStorage {
        init_module(&arg);
        let random_address2 = @0x9876;

        let random_address3 = @hem_acc;
        let random_address4 = @0x9822;

        let vec = vector::empty<address>();
        vector::push_back(&mut vec, random_address4);
        vector::push_back(&mut vec, random_address2);
        vector::push_back(&mut vec, random_address3);
        bulk_add_to_whitelist(&arg, copy vec);

        assert!(is_whitelisted(random_address4), 1);
        assert!(is_whitelisted(random_address2), 1);
        assert!(is_whitelisted(random_address3), 1);

        let (burn, mint) = aptos_framework::aptos_coin::initialize_for_test(&framework);
        let coin = coin::mint<AptosCoin>(1000000000, &mint);
        account::create_account_for_test(signer::address_of(&arg));
        coin::register<AptosCoin>(&arg);
        coin::deposit(signer::address_of(&arg), coin);

        deposit(&arg, 10000);
        transfer_funds(&arg, @hem_acc, random_address4, 50);

        assert!(get_balance(@hem_acc) == 9950, 1);
        assert!(get_balance(random_address4) == 50, 1);

        coin::destroy_burn_cap(burn);
        coin::destroy_mint_cap(mint);
    }
}
