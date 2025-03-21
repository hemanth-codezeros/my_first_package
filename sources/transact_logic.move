module Hem_Acc::transact{
    // Deposit funds (only for whitelisted addresses)
    public entry fun deposit(depositor: &signer, amount: u64) acquires Whitelist, FundStorage {
        let depositor_address = signer::address_of(depositor);
        let whitelist = borrow_global<Whitelist>(@Hem_Acc);
        assert!(vector::contains(&whitelist.addresses, &depositor_address), "Address not whitelisted");

        let fund_storage = borrow_global_mut<FundStorage>(@Hem_Acc);
        fund_storage.balance = fund_storage.balance + amount;
        event::emit_event(&mut fund_storage.deposit_events, DepositEvent { depositor: depositor_address, amount });
    }

    // Withdraw funds (admin-only)
    public entry fun withdraw(admin: &signer, amount: u64) acquires FundStorage {
        assert!(signer::address_of(admin) == @Hem_Acc, "Only admin can perform this action");
        let fund_storage = borrow_global_mut<FundStorage>(@Hem_Acc);
        assert!(fund_storage.balance >= amount, "Insufficient balance");
        fund_storage.balance = fund_storage.balance - amount;
    }
}