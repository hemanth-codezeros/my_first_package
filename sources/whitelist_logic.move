module Hem_Acc::whitelist_deposit {
    use std::signer;
    use std::vector;
    use aptos_framework::account;
    use aptos_framework::event;

    const INSUFFICIENT_BALANCE: u64 = 41;
    const ADMIN_ONLY_ACTION: u64 = 42;
    const NOT_WHITELISTED: u64 = 43;


    // Resource to store whitelisted addresses
    struct Whitelist has key {
        addresses: vector<address>,
        whitelist_events: event::EventHandle<WhitelistEvent>,
    }

    // Resource to store funds in the resource account
    struct FundStorage has key {
        user_funds: vector<UserFund>,
        deposit_events: event::EventHandle<DepositEvent>,
        withdraw_events: event::EventHandle<WithdrawEvent>,
    }

    struct UserFund has store {
        balance: u64,
        address: address,
    }

    // Event for logging whitelist modifications
    struct WhitelistEvent has drop, store {
        address: address,
        added: bool, // true if added, false if removed
    }

    // Event for logging deposits
    struct DepositEvent has drop, store {
        depositor: address,
        amount: u64,
    }

    // Event for logging withdrawl
    struct WithdrawEvent has drop, store {
        withdraw_address: address,
        amount: u64,
    }

    // Initializing the contract
    public entry fun initialize(admin: &signer) {
        // Creating a resource account for storing funds
        let (resource_signer, _resource_signer_cap) = account::create_resource_account(admin, b"fund_storage");
        let fund_storage = FundStorage {
            user_funds: vector::empty<UserFund>(),
            deposit_events: account::new_event_handle<DepositEvent>(&resource_signer),
            withdraw_events: account::new_event_handle<WithdrawEvent>(&resource_signer),
        };
        move_to(&resource_signer, fund_storage);

        // Initialize the whitelist
        let whitelist = Whitelist {
            addresses: vector::empty<address>(),
            whitelist_events: account::new_event_handle<WhitelistEvent>(admin),
        };
        move_to(admin, whitelist);
    }

    // Add an address to the whitelist (admin-only)
    public entry fun add_to_whitelist(admin: &signer, address: address) acquires Whitelist {
        assert!(signer::address_of(admin) == @Hem_Acc,ADMIN_ONLY_ACTION);
        let whitelist = borrow_global_mut<Whitelist>(@Hem_Acc);
        vector::push_back(&mut whitelist.addresses, address);
        event::emit_event(&mut whitelist.whitelist_events, WhitelistEvent { address, added: true });
    }

    // Remove an address from the whitelist (admin-only)
    public entry fun remove_from_whitelist(admin: &signer, address: address) acquires Whitelist {
        assert!(signer::address_of(admin) == @Hem_Acc, ADMIN_ONLY_ACTION);
        let whitelist = borrow_global_mut<Whitelist>(@Hem_Acc);
        let (_exists,index) = vector::index_of(&whitelist.addresses, &address);
        vector::remove(&mut whitelist.addresses, index);
        event::emit_event(&mut whitelist.whitelist_events, WhitelistEvent { address, added: false });
    }

    // Bulk add addresses to the whitelist (admin-only)
    public entry fun bulk_add_to_whitelist(admin: &signer, addresses: vector<address>) acquires Whitelist {
        assert!(signer::address_of(admin) == @Hem_Acc, ADMIN_ONLY_ACTION);
        let whitelist = borrow_global_mut<Whitelist>(@Hem_Acc);
        let i = 0;
        while (i < vector::length(&addresses)) {
            let address = *vector::borrow(&addresses, i);
            vector::push_back(&mut whitelist.addresses, address);
            event::emit_event(&mut whitelist.whitelist_events, WhitelistEvent { address, added: true });
            i = i + 1;
        }
    }

    // Bulk remove addresses from the whitelist (admin-only)
    public entry fun bulk_remove_from_whitelist(admin: &signer, addresses: vector<address>) acquires Whitelist {
        assert!(signer::address_of(admin) == @Hem_Acc, ADMIN_ONLY_ACTION);
        let whitelist = borrow_global_mut<Whitelist>(@Hem_Acc);
        let i = 0;
        while (i < vector::length(&addresses)) {
            let address = *vector::borrow(&addresses, i);
            let (_exists,index) = vector::index_of(&whitelist.addresses, &address);
            vector::remove(&mut whitelist.addresses, index);
            event::emit_event(&mut whitelist.whitelist_events, WhitelistEvent { address, added: false });
            i = i + 1;
        }
    }

    // Transact logic to deposit funds from resource account for whitlisted accounts
    // Deposit funds (only for whitelisted addresses)
    public entry fun deposit(depositor: &signer, amount: u64) acquires Whitelist, FundStorage {
        let depositor_address = signer::address_of(depositor);
        let whitelist = borrow_global<Whitelist>(@Hem_Acc);
        assert!(vector::contains(&whitelist.addresses, &depositor_address), NOT_WHITELISTED);

        let fund_storage = borrow_global_mut<FundStorage>(@Hem_Acc);
        // let user_funds =  fund_storage.user_funds;
        let i : u64= 0;
        let length = vector::length(&fund_storage.user_funds);
        while (i < length) {
            let element = vector::borrow_mut(&mut fund_storage.user_funds, i);
            if (signer::address_of(depositor) == element.address){
                element.balance = element.balance + amount;
                event::emit_event(&mut fund_storage.deposit_events, DepositEvent { depositor: depositor_address, amount });
                break
            };
            i = i + 1;
        }
    }

    // Withdraw funds (admin-only)
    public entry fun withdraw(admin: &signer, amount: u64, withdraw_address: address) acquires FundStorage {
        assert!(signer::address_of(admin) == @Hem_Acc, ADMIN_ONLY_ACTION);
        let fund_storage = borrow_global_mut<FundStorage>(@Hem_Acc);
        // assert!(fund_storage.balance <= amount, "Insufficient balance");
        // let user_funds =  fund_storage.user_funds;

        let i = 0;
        let length = vector::length(&fund_storage.user_funds);
        while (i < length) {
            let element = vector::borrow_mut(&mut fund_storage.user_funds, i);
            if (withdraw_address == element.address){
                assert!(element.balance >= amount, INSUFFICIENT_BALANCE);
                element.balance = element.balance - amount;
            event::emit_event(&mut fund_storage.withdraw_events, WithdrawEvent { withdraw_address: withdraw_address, amount });
                break;
            };
            i = i + 1;
        }
    }

    // Function to transfer funds from withdraw_address to despositor_address
    public entry fun transfer_funds(admin: &signer, withdraw_address: address, depositor_address: address, amount: u64) acquires FundStorage {
        assert!(signer::address_of(admin) == @Hem_Acc, ADMIN_ONLY_ACTION);
        let fund_storage = borrow_global_mut<FundStorage>(@Hem_Acc);
        // let user_funds =  fund_storage.user_funds;
        let i = 0;
        let length = vector::length(&fund_storage.user_funds);
        while (i < length) {
            let element = vector::borrow_mut(&mut fund_storage.user_funds, i);
            if (withdraw_address == element.address){
                assert!(element.balance >= amount, INSUFFICIENT_BALANCE);
                element.balance = element.balance - amount;
                event::emit_event(&mut fund_storage.withdraw_events, WithdrawEvent { withdraw_address: withdraw_address, amount });
            };

            if (depositor_address == element.address){
                element.balance = element.balance + amount;
                event::emit_event(&mut fund_storage.deposit_events, DepositEvent { depositor: depositor_address, amount });
            };
            i = i + 1;
        }
    }

    // View function to check if an address is whitelisted
    public fun is_whitelisted(address: address): bool acquires Whitelist {
        let whitelist = borrow_global<Whitelist>(@Hem_Acc);
        vector::contains(&whitelist.addresses, &address)
    }

    // View function to get the current balance
    public fun get_balance(address: address): u64 acquires FundStorage {
        let fund_storage = borrow_global<FundStorage>(@Hem_Acc);
        // let user_funds =  fund_storage.user_funds;
        let i : u64 = 0;
        let length = vector::length(&fund_storage.user_funds);
        let result: u64 = 0 ;
        while (i < length) {
            let element = vector::borrow(&fund_storage.user_funds, i);
            if (address == element.address){
                result = element.balance;
            };
        };
        result
    }
}

