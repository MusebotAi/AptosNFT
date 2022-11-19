/// This module is used to create a primary market that automatically create NFTs and allows users to mint.
/// module owner can modify the rule's config to control mint Strategy
module mint_nft::mintone {
    use std::error;
    use std::signer;
    use std::string::{Self, String};
    use std::vector;

    use aptos_framework::account;
    use aptos_framework::event::{Self, EventHandle};
    use aptos_framework::timestamp;
    use aptos_token::token::{Self, TokenDataId};
    use aptos_framework::coin;
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::resource_account;
    #[test_only]
    use aptos_framework::account::create_account_for_test;
    // use aptos_std::ed25519::ValidatedPublicKey;

    /// Action not authorized because the signer is not the owner of this module
    const ENOT_AUTHORIZED: u64 = 1;
    /// argument for module is invalid
    const EINVALID_STRATEGYS: u64 = 2;
    /// The collection minting is disabled
    const EMINTING_DISABLED: u64 = 3;
    /// module doesn't init
    const ENEED_INIT: u64 = 4;

    // This struct stores the token receiver's address and token_data_id in the event of token minting
    struct TokenMintingEvent has drop, store {
        token_receiver_address: address,
        token_data_id: TokenDataId,
    }

    struct NftInfo has key {
        signer_cap: account::SignerCapability,
        collection_name: String,
        token_pre: String,
        used: u64,
        token_minting_events: EventHandle<TokenMintingEvent>,
    }


    fun init_module(resource_account: &signer) {
        let resource_signer_cap = resource_account::retrieve_resource_account_cap(resource_account, @source_addr);
        let resource_signer = account::create_signer_with_capability(&resource_signer_cap);
        let minter_address = signer::address_of(resource_account);
        let collection_name = string::utf8(b"musebot.ai");
        let maximum_supply = 0;
        let mutate_setting = vector<bool>[ false, false, false ];
        token::create_collection(resource_account, collection_name, collection_name, collection_name, maximum_supply, mutate_setting);
        if (!exists<NftInfo>(minter_address)){
            move_to(resource_account, NftInfo {
                signer_cap: resource_signer_cap,
                collection_name: collection_name,
                token_pre: string::utf8(b"token #"),
                used: 0,
                token_minting_events: account::new_event_handle<TokenMintingEvent>(&resource_signer),
            });
        };
    }

    public entry fun modify_module_by_owner(minter: &signer,
        collection_name: String,
        token_pre: String) acquires NftInfo {

        let minter_address = signer::address_of(minter);
        assert!(minter_address == @source_addr, error::permission_denied(ENOT_AUTHORIZED));

        let nftinfo = borrow_global_mut<NftInfo>(@mint_nft);
        let resource_signer = account::create_signer_with_capability(&nftinfo.signer_cap);
        let resource_account_address = signer::address_of(&resource_signer);
        // create the resource account that we'll use to create tokens
        // change source_addr to the actually account that called `create_resource_account`
        if (! token::check_collection_exists(resource_account_address,collection_name)) {
            let maximum_supply = 0;
            let mutate_setting = vector<bool>[ false, false, false ];
            token::create_collection(&resource_signer, collection_name, collection_name, collection_name, maximum_supply, mutate_setting);
        };
        
        nftinfo.collection_name = collection_name;
        nftinfo.token_pre = token_pre;
    }

    public entry fun mint_nft(receiver: &signer,token_uri: String) acquires NftInfo {

        let receiver_addr = signer::address_of(receiver);

        // get the collection minter and check if the collection minting is disabled or expired
        let nftinfo = borrow_global_mut<NftInfo>(@mint_nft);
        
        // create nft
        let str_used = get_str_from_number(nftinfo.used+1);
        let token_name = nftinfo.token_pre;
        string::append(&mut token_name,str_used);
        let resource_signer = account::create_signer_with_capability(&nftinfo.signer_cap);
        let resource_account_address = signer::address_of(&resource_signer);
        let token_data_id = token::create_tokendata(
            &resource_signer,
            nftinfo.collection_name,
            token_name,
            token_name,
            0,
            token_uri,
            resource_account_address,
            100,
            5,
            // we don't allow any mutation to the token
            token::create_token_mutability_config(
                &vector<bool>[ false, false, false, false, false ]
            ),
            vector::empty<String>(),
            vector::empty<vector<u8>>(),
            vector::empty<String>(),
        );

        // mint token to the receiver
        let token_id = token::mint_token(&resource_signer, token_data_id, 1);
        if(resource_account_address != receiver_addr) {
            token::direct_transfer(&resource_signer, receiver, token_id, 1);
        };
        event::emit_event<TokenMintingEvent>(
            &mut nftinfo.token_minting_events,
            TokenMintingEvent {
                token_receiver_address: receiver_addr,
                token_data_id: token_data_id,
            }
        );

        nftinfo.used = nftinfo.used + 1;
    }

    fun get_str_from_number(n :u64): String {
        let nstrs = string::utf8(b"0123456789");
        let i: u64 = 10;
        let str_number = string::utf8(b"");
        loop {
            let np = n % i;
            n = n / i;
            string::insert(&mut str_number,0,string::sub_string(&nstrs,np,np+1));
            if (n == 0) break;
        };
        str_number
    }

    #[test_only]
    public fun test_setup(origin_account: &signer,mint_account: &signer,aptos_framework: &signer) {
        // set up global time for testing purpose
        timestamp::set_time_has_started_for_testing(aptos_framework);
        create_account_for_test(signer::address_of(origin_account));
        // // create a resource account from the origin account, mocking the module publishing process
        resource_account::create_resource_account(origin_account, vector::empty<u8>(), vector::empty<u8>());
        init_module(mint_account);
        coin::register<AptosCoin>(origin_account);
    }


    #[test(origin_account=@0x0a6f65c5389cb25206b0778b0411728663f1533da8a51f36d5b14db16b18dbc4, mint_account=@0xb00b2aef1ffae7256e4fdc345903a6102e7107d9b1ed96a451ad6c110347ce78, aptos_framework = @aptos_framework)]
    public fun test_modify_module(origin_account: &signer,mint_account: &signer,aptos_framework: &signer) acquires NftInfo {
        test_setup(origin_account,mint_account,aptos_framework);
        let collection_name = string::utf8(b"test_collection");
        let token_pre = string::utf8(b"ttt");
        modify_module_by_owner(origin_account,collection_name,token_pre);
        let nftinfo = borrow_global_mut<NftInfo>(@mint_nft);
        assert!(nftinfo.collection_name == collection_name,1);
        assert!(nftinfo.token_pre == token_pre,1);
        aptos_std::debug::print<NftInfo>(nftinfo);
    }

    #[test(origin_account=@0x0a6f65c5389cb25206b0778b0411728663f1533da8a51f36d5b14db16b18dbc4, mint_account=@0xb00b2aef1ffae7256e4fdc345903a6102e7107d9b1ed96a451ad6c110347ce78, aptos_framework = @aptos_framework, recv_account=@0x3443345f)]
    public fun test_mint_normal(origin_account: &signer,mint_account: &signer,aptos_framework: &signer,recv_account: &signer) acquires NftInfo {
        test_setup(origin_account,mint_account,aptos_framework);
        create_account_for_test(signer::address_of(recv_account));
        mint_nft(recv_account,string::utf8(b"https://stacktrace.top/imgs/1.json"));
        let nftinfo = borrow_global_mut<NftInfo>(@mint_nft);
        assert!(nftinfo.used == 1,1);
        aptos_std::debug::print<NftInfo>(nftinfo);
    }
}
