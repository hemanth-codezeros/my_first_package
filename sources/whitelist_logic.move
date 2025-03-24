module Hem_Acc::whitelist_deposit {
    use std::signer;
    use std::vector;
    use aptos_framework::account;
    use aptos_framework::event;
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

    const SEED_FOR_RESOURCE_ACCOUNT: vector<u8> = b"fund_storage";

    // Resource to store whitelisted addresses
    struct Whitelist has key {
        addresses: vector<address>, // only whitelisted addresses
        whitelist_events: event::EventHandle<WhitelistEvent>,
    }

    // Resource to store funds in the resource account
    struct FundStorage has key {
        user_funds: vector<UserFund>,
        deposit_events: event::EventHandle<DepositEvent>,
        withdraw_events: event::EventHandle<WithdrawEvent>,
    }

    // Create & store the SignerCapability for later use
    struct ResourceCapabilityHolder has key {
        signer_cap: account::SignerCapability,
    }

    // Fund for each user
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
        let (resource_signer, resource_signer_cap) = account::create_resource_account(admin, SEED_FOR_RESOURCE_ACCOUNT);

        // Store the SignerCapability in the admin's account
        move_to(admin, ResourceCapabilityHolder { signer_cap: resource_signer_cap });

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
        assert!(signer::address_of(admin) == @Hem_Acc, ADMIN_ONLY_ACTION);
        let whitelist = borrow_global_mut<Whitelist>(@Hem_Acc);
        vector::push_back(&mut whitelist.addresses, address);
        event::emit_event(&mut whitelist.whitelist_events, WhitelistEvent { address, added: true });
    }

    // Remove an address from the whitelist (admin-only)
    public entry fun remove_from_whitelist(admin: &signer, address: address) acquires Whitelist {
        assert!(signer::address_of(admin) == @Hem_Acc, ADMIN_ONLY_ACTION);
        let whitelist = borrow_global_mut<Whitelist>(@Hem_Acc);
        let (exists,index) = vector::index_of(&whitelist.addresses, &address);
        assert!(!exists, NOT_PRESENT_IN_WHITELISTED);
        vector::remove(&mut whitelist.addresses, index);
        event::emit_event(&mut whitelist.whitelist_events, WhitelistEvent { address, added: false });
        
    }

    // Bulk add addresses to the whitelist (admin-only)
    public entry fun bulk_add_to_whitelist(admin: &signer, addresses: vector<address>) acquires Whitelist {
        assert!(signer::address_of(admin) == @Hem_Acc, ADMIN_ONLY_ACTION);
        let whitelist = borrow_global_mut<Whitelist>(@Hem_Acc);
        let i = 0;
        let length = vector::length(&addresses);

        while (i < length) {
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
        let length = vector::length(&addresses);
        while (i < length) {
            let address = *vector::borrow(&addresses, i);
            let (exists,index) = vector::index_of(&whitelist.addresses, &address);
            assert!(!exists, NOT_PRESENT_IN_WHITELISTED);
            vector::remove(&mut whitelist.addresses, index);
            event::emit_event(&mut whitelist.whitelist_events, WhitelistEvent { address, added: false });
            i = i + 1;
        }
    }

    // Transact logic to deposit funds from resource account for whitlisted accounts
    // Deposit funds (only for whitelisted addresses)
    public entry fun deposit(depositor: &signer, amount: u64) acquires Whitelist, FundStorage, ResourceCapabilityHolder {
        let depositor_address = signer::address_of(depositor);
        let whitelist = borrow_global<Whitelist>(@Hem_Acc);
        assert!(vector::contains(&whitelist.addresses, &depositor_address), NOT_WHITELISTED);


        let signer_cap = &borrow_global<ResourceCapabilityHolder>(@Hem_Acc).signer_cap;
        let resource_signer = account::create_signer_with_capability(signer_cap);

        let fund_storage = borrow_global_mut<FundStorage>(signer::address_of(&resource_signer));
        let i : u64= 0;
        let length = vector::length(&fund_storage.user_funds);
        while (i < length) {
            let element = vector::borrow_mut(&mut fund_storage.user_funds, i);
            if (signer::address_of(depositor) == element.address){
                coin::transfer<AptosCoin>(depositor, signer::address_of(&resource_signer), amount);
                element.balance = element.balance + amount;
                event::emit_event(&mut fund_storage.deposit_events, DepositEvent { depositor: depositor_address, amount });
                break
            };
            i = i + 1;
        }
    }

    // Withdraw funds (admin-only)
    public entry fun withdraw(admin: &signer, amount: u64, withdraw_address: address) acquires FundStorage, ResourceCapabilityHolder {
        assert!(signer::address_of(admin) == @Hem_Acc, ADMIN_ONLY_ACTION);

        let signer_cap = &borrow_global<ResourceCapabilityHolder>(@Hem_Acc).signer_cap;
        let resource_signer = account::create_signer_with_capability(signer_cap);

        let fund_storage = borrow_global_mut<FundStorage>(signer::address_of(&resource_signer));
        let i = 0;
        let length = vector::length(&fund_storage.user_funds);
        while (i < length) {
            let element = vector::borrow_mut(&mut fund_storage.user_funds, i);
            if (withdraw_address == element.address){
                assert!(element.balance >= amount, INSUFFICIENT_BALANCE);
                coin::transfer<AptosCoin>(&resource_signer, @Hem_Acc, amount);
                element.balance = element.balance - amount;
                event::emit_event(&mut fund_storage.withdraw_events, WithdrawEvent { withdraw_address: withdraw_address, amount });
                break;
            };
            i = i + 1;
        }
    }

    // Function to transfer funds from withdraw_address to despositor_address
    public entry fun transfer_funds(admin: &signer, withdraw_address: address, depositor_address: address, amount: u64) acquires FundStorage, ResourceCapabilityHolder {
        assert!(signer::address_of(admin) == @Hem_Acc, ADMIN_ONLY_ACTION);
        let signer_cap = &borrow_global<ResourceCapabilityHolder>(@Hem_Acc).signer_cap;
        let resource_signer = account::create_signer_with_capability(signer_cap);

        let fund_storage = borrow_global_mut<FundStorage>(signer::address_of(&resource_signer));
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
    #[view]
    public fun is_whitelisted(address: address): bool acquires Whitelist {
        let whitelist = borrow_global<Whitelist>(@Hem_Acc);
        vector::contains(&whitelist.addresses, &address)
    }

    // View function to get the current balance
    #[view]
    public fun get_balance(address: address): u64 acquires FundStorage, ResourceCapabilityHolder {
        let signer_cap = &borrow_global<ResourceCapabilityHolder>(@Hem_Acc).signer_cap;
        let resource_signer = account::create_signer_with_capability(signer_cap);

        let fund_storage = borrow_global_mut<FundStorage>(signer::address_of(&resource_signer));
        let i : u64 = 0;
        let length = vector::length(&fund_storage.user_funds);
        let result: u64 = 0 ;
        while (i < length) {
            let element = vector::borrow(&fund_storage.user_funds, i);
            if (address == element.address){
                result = element.balance;
                break;
            };
        };
        result
    }
}

