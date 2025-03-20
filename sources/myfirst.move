module MyProject::whitelist_deposit {
    use std::signer;
    use std::vector;
    use aptos_framework::account;
    use aptos_framework::event;

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

    // Resource to store whitelisted addresses
    struct Whitelist has key {
        addresses: vector<address>,
        whitelist_events: event::EventHandle<WhitelistEvent>,
    }

    // Resource to store funds in the resource account
    struct FundStorage has key {
        balance: u64,
        deposit_events: event::EventHandle<DepositEvent>,
    }

    // Initialize the contract
    public fun initialize(admin: &signer) {
        // Create a resource account for storing funds
        let (resource_signer, resource_signer_cap) = account::create_resource_account(admin, b"fund_storage");
        let fund_storage = FundStorage {
            balance: 0,
            deposit_events: account::new_event_handle<DepositEvent>(&resource_signer),
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
        assert!(signer::address_of(admin) == @MyProject, "Only admin can perform this action");
        let whitelist = borrow_global_mut<Whitelist>(@MyProject);
        vector::push_back(&mut whitelist.addresses, address);
        event::emit_event(&mut whitelist.whitelist_events, WhitelistEvent { address, added: true });
    }

    // Remove an address from the whitelist (admin-only)
    public entry fun remove_from_whitelist(admin: &signer, address: address) acquires Whitelist {
        assert!(signer::address_of(admin) == @MyProject, "Only admin can perform this action");
        let whitelist = borrow_global_mut<Whitelist>(@MyProject);
        let index = vector::index_of(&whitelist.addresses, &address);
        vector::remove(&mut whitelist.addresses, index);
        event::emit_event(&mut whitelist.whitelist_events, WhitelistEvent { address, added: false });
    }

    // Bulk add addresses to the whitelist (admin-only)
    public entry fun bulk_add_to_whitelist(admin: &signer, addresses: vector<address>) acquires Whitelist {
        assert!(signer::address_of(admin) == @MyProject, "Only admin can perform this action");
        let whitelist = borrow_global_mut<Whitelist>(@MyProject);
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
        assert!(signer::address_of(admin) == @MyProject, "Only admin can perform this action");
        let whitelist = borrow_global_mut<Whitelist>(@MyProject);
        let i = 0;
        while (i < vector::length(&addresses)) {
            let address = *vector::borrow(&addresses, i);
            let index = vector::index_of(&whitelist.addresses, &address);
            vector::remove(&mut whitelist.addresses, index);
            event::emit_event(&mut whitelist.whitelist_events, WhitelistEvent { address, added: false });
            i = i + 1;
        }
    }

    // Deposit funds (only for whitelisted addresses)
    public entry fun deposit(depositor: &signer, amount: u64) acquires Whitelist, FundStorage {
        let depositor_address = signer::address_of(depositor);
        let whitelist = borrow_global<Whitelist>(@MyProject);
        assert!(vector::contains(&whitelist.addresses, &depositor_address), "Address not whitelisted");

        let fund_storage = borrow_global_mut<FundStorage>(@MyProject);
        fund_storage.balance = fund_storage.balance + amount;
        event::emit_event(&mut fund_storage.deposit_events, DepositEvent { depositor: depositor_address, amount });
    }

    // Withdraw funds (admin-only)
    public entry fun withdraw(admin: &signer, amount: u64) acquires FundStorage {
        assert!(signer::address_of(admin) == @MyProject, "Only admin can perform this action");
        let fund_storage = borrow_global_mut<FundStorage>(@MyProject);
        assert!(fund_storage.balance >= amount, "Insufficient balance");
        fund_storage.balance = fund_storage.balance - amount;
    }

    // View function to check if an address is whitelisted
    public fun is_whitelisted(address: address): bool acquires Whitelist {
        let whitelist = borrow_global<Whitelist>(@MyProject);
        vector::contains(&whitelist.addresses, &address)
    }

    // View function to get the current balance
    public fun get_balance(): u64 acquires FundStorage {
        let fund_storage = borrow_global<FundStorage>(@MyProject);
        fund_storage.balance
    }
}

