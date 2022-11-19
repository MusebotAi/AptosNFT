module useraddr::minting {
    use std::error;
    use std::signer;
    use std::string::{Self, String};
    use std::vector;

    use aptos_framework::account;
    use aptos_framework::event::{Self, EventHandle};
    use aptos_token::token::{Self, TokenDataId};
    use aptos_framework::coin;
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::aptos_account;
    #[test_only]
    use aptos_framework::account::create_account_for_test;
    // use aptos_std::ed25519::ValidatedPublicKey;
    
    // This struct stores the token receiver's address and token_data_id in the event of token minting
    struct TokenMintingEvent has drop, store {
        token_receiver_address: address,
        token_data_id: TokenDataId,
    }

    // This struct stores an NFT collection's relevant information
    struct CollectionTokenMinter has key {
        signer_cap: account::SignerCapability,
        collection_name: String,
        token_pre: String,
        pre_uri: String,
        total_supply: u64,
        used: u64,
        price: u64,
        token_minting_events: EventHandle<TokenMintingEvent>,
    }

    /// Action not authorized because the signer is not the owner of this module
    const ENOT_AUTHORIZED: u64 = 1;
    /// argument for module is invalid
    const EINVALID_STRATEGYS: u64 = 2;
    /// The collection minting is disabled
    const EMINTING_DISABLED: u64 = 3;
    /// module doesn't init
    const ENEED_INIT: u64 = 4;
    /// sale not start yet
    const ENOT_INTIME: u64 = 5;
    /// not in white list
    const ENOT_INWHITLIST: u64 = 6;
    /// not enough tokens
    const ENFT_EMPTY: u64 = 7;
    /// insufficient balance
    const EINSUFFICIENT_FUND: u64 = 8;

    

    fun init_module(user: &signer) {
        let (resource, resource_signer_cap) = account::create_resource_account(user, vector::empty<u8>());
        let collection_name = string::utf8(b"self_collections");
        // insert begin for modify params like below
        let pre_uri: String = string::utf8(b"xxx");
        let total_supply: u64 = 15;
        let price: u64 = 0;
        // insert end
        let maximum_supply = 0;
        let mutate_setting = vector<bool>[ false, false, false ];
        token::create_collection(&resource, collection_name, collection_name, collection_name, maximum_supply, mutate_setting);
        if (!exists<CollectionTokenMinter>(@useraddr)){
            move_to(user, CollectionTokenMinter {
                signer_cap: resource_signer_cap,
                collection_name,
                token_pre: string::utf8(b"token #"),
                pre_uri,
                total_supply,
                used: 0,
                price,
                token_minting_events: account::new_event_handle<TokenMintingEvent>(user),
            });
        };
    }

    public entry fun modify_module_by_owner(minter: &signer,
        collection_name: String,
        token_pre: String,
        pre_uri: String,
        total_supply: u64,
        price: u64,
        used: u64) acquires CollectionTokenMinter {

        let minter_address = signer::address_of(minter);
        assert!(minter_address == @useraddr, error::permission_denied(ENOT_AUTHORIZED));

        let collection_token_minter = borrow_global_mut<CollectionTokenMinter>(@useraddr);
        
        // collection_token_minter.collection_name = collection_name;
        collection_token_minter.pre_uri = pre_uri;
        // collection_token_minter.token_pre = token_pre;
        collection_token_minter.total_supply = total_supply;
        collection_token_minter.price = price;
        if(used == 0){
            collection_token_minter.used = 0;
        };
    }

    public entry fun mint_nft(receiver: &signer) acquires CollectionTokenMinter {

        let receiver_addr = signer::address_of(receiver);

        // get the collection minter and check if the collection minting is disabled or expired
        let collection_token_minter = borrow_global_mut<CollectionTokenMinter>(@useraddr);
        assert!(collection_token_minter.total_supply > collection_token_minter.used, error::resource_exhausted(ENFT_EMPTY));

        let resource_signer = account::create_signer_with_capability(&collection_token_minter.signer_cap);
        let resource_account_address = signer::address_of(&resource_signer);

        // create nft
        let token_uri = collection_token_minter.pre_uri;
        let str_used = get_str_from_number(collection_token_minter.used+1);
        string::append(&mut token_uri,str_used);
        string::append(&mut token_uri,string::utf8(b".json"));
        let token_name = collection_token_minter.token_pre;
        string::append(&mut token_name,str_used);
        let token_data_id = token::create_tokendata(
            &resource_signer,
            collection_token_minter.collection_name,
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

        // fee process
        if (collection_token_minter.price > 0 && receiver_addr != @useraddr) {
            assert!(coin::balance<AptosCoin>(receiver_addr) > collection_token_minter.price, EINSUFFICIENT_FUND);
            aptos_account::transfer(receiver,@useraddr,collection_token_minter.price);
        };

        // mint token to the receiver
        let token_id = token::mint_token(&resource_signer, token_data_id, 1);
        if(resource_account_address != receiver_addr) {
            token::direct_transfer(&resource_signer, receiver, token_id, 1);
        };
        event::emit_event<TokenMintingEvent>(
            &mut collection_token_minter.token_minting_events,
            TokenMintingEvent {
                token_receiver_address: receiver_addr,
                token_data_id: token_data_id,
            }
        );
        collection_token_minter.used = collection_token_minter.used + 1;
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
}
