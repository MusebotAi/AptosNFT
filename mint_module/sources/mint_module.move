/// This module is used to create a primary market that automatically create NFTs and allows users to mint.
/// module owner can modify the rule's config to control mint Strategy
module mint_nft::minting {
    use std::error;
    use std::signer;
    use std::string::{Self, String};
    use std::vector;

    use aptos_std::table::{Self, Table};
    use aptos_framework::account;
    use aptos_framework::event::{Self, EventHandle};
    use aptos_framework::timestamp;
    use aptos_token::token::{Self, TokenDataId};
    use aptos_framework::coin;
    use aptos_framework::code;
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::aptos_account;
    use aptos_framework::resource_account;
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
        white_list: vector<address>,
        collection_name: String,
        token_pre: String,
        pre_uri: String,
        presale_timestamp: u64,
        sale_timestamp: u64,
        total_supply: u64,
        used: u64,
        strategy_ids: vector<u64>,
        mint_strategys: Table<u64,MintStrategy>,
        mint_random: bool,
        minting_enabled: bool,
        token_minting_events: EventHandle<TokenMintingEvent>,
    }

    struct Random has key {
        rand_number: u64,
        last_total: u64,
        rand_pool: vector<u64>,
    }

    const RESERVED: u8 = 0;
    const WHITELIST: u8 = 1;
    const NORMAL: u8 = 2;

    struct MintStrategy has drop,store {
        type: u8,
        supply: u64,
        used: u64,
        fee: u64,
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

    fun init_module(resource_account: &signer) {
        let resource_signer_cap = resource_account::retrieve_resource_account_cap(resource_account, @source_addr);
        let resource_signer = account::create_signer_with_capability(&resource_signer_cap);
        let minter_address = signer::address_of(resource_account);
        let collection_name = string::utf8(b"nft collection");
        let maximum_supply = 0;
        let mutate_setting = vector<bool>[ false, false, false ];
        coin::register<AptosCoin>(resource_account);
        token::create_collection(resource_account, collection_name, collection_name, collection_name, maximum_supply, mutate_setting);
        if (!exists<CollectionTokenMinter>(minter_address)){
            move_to(resource_account, CollectionTokenMinter {
                signer_cap: resource_signer_cap,
                white_list: vector::empty<address>(),
                collection_name: string::utf8(b"collections"),
                token_pre: string::utf8(b"token #"),
                pre_uri: string::utf8(b""),
                presale_timestamp: 0,
                sale_timestamp: 0,
                total_supply: 0,
                used: 0,
                strategy_ids: vector::empty<u64>(),
                mint_strategys: table::new<u64,MintStrategy>(),
                mint_random: false,
                minting_enabled: false,
                token_minting_events: account::new_event_handle<TokenMintingEvent>(&resource_signer),
            });
        };

        if (!exists<Random>(minter_address)) {
            move_to(resource_account, Random {
                rand_number: timestamp::now_seconds(),
                last_total: 0,
                rand_pool: vector::empty<u64>(),
            })
        };
    }

    public entry fun modify_module_by_owner(minter: &signer,
        collection_name: String,
        token_pre: String,
        pre_uri: String,
        presale_timestamp: u64,
        sale_timestamp: u64,
        total_supply: u64,
        mint_random: bool,
        minting_enabled: bool,
        strategy_id: vector<u64>,
        strategy_types: vector<u8>,
        strategy_supply: vector<u64>,
        strategy_fee: vector<u64>,
        white_list: vector<address>) acquires CollectionTokenMinter,Random {

        let minter_address = signer::address_of(minter);
        assert!(minter_address == @source_addr, error::permission_denied(ENOT_AUTHORIZED));

        let collection_token_minter = borrow_global_mut<CollectionTokenMinter>(@mint_nft);
        let resource_signer = account::create_signer_with_capability(&collection_token_minter.signer_cap);
        let resource_account_address = signer::address_of(&resource_signer);
        // create the resource account that we'll use to create tokens
        // change source_addr to the actually account that called `create_resource_account`
        if (! token::check_collection_exists(resource_account_address,collection_name)) {
            let maximum_supply = 0;
            let mutate_setting = vector<bool>[ false, false, false ];
            token::create_collection(&resource_signer, collection_name, collection_name, collection_name, maximum_supply, mutate_setting);
        };


        assert!(vector::length<u64>(&strategy_id) == vector::length<u8>(&strategy_types), error::invalid_argument(EINVALID_STRATEGYS));
        assert!(vector::length<u64>(&strategy_id) == vector::length<u64>(&strategy_supply), error::invalid_argument(EINVALID_STRATEGYS));
        assert!(vector::length<u64>(&strategy_id) == vector::length<u64>(&strategy_fee), error::invalid_argument(EINVALID_STRATEGYS));

        
        
        collection_token_minter.collection_name = collection_name;
        collection_token_minter.minting_enabled = minting_enabled;
        collection_token_minter.pre_uri = pre_uri;
        collection_token_minter.token_pre = token_pre;
        collection_token_minter.white_list = white_list;
        collection_token_minter.presale_timestamp = presale_timestamp;
        collection_token_minter.sale_timestamp = sale_timestamp;
        collection_token_minter.total_supply = total_supply;
        collection_token_minter.mint_random = mint_random;
        collection_token_minter.minting_enabled = minting_enabled;

        let strategy_ids = vector::empty<u64>();
        let len = vector::length(&strategy_id);
        let pos: u64 = 0;
        while(pos < len) {
            let id: u64 = *vector::borrow(&strategy_id, pos);
            vector::push_back(&mut strategy_ids,id);
            let used: u64 = 0;
            if (table::contains(&collection_token_minter.mint_strategys,id)) {
                used = table::borrow(&collection_token_minter.mint_strategys,id).used;
                table::remove(&mut collection_token_minter.mint_strategys,id);
            };
            table::add(&mut collection_token_minter.mint_strategys,id,MintStrategy {
                type: *vector::borrow(&strategy_types,pos),
                supply: *vector::borrow(&strategy_supply,pos),
                used: used,
                fee: *vector::borrow(&strategy_fee,pos),
            });
            pos = pos + 1;
        };
        while((!vector::is_empty(&collection_token_minter.strategy_ids))) {
            let id: u64 = vector::pop_back(&mut collection_token_minter.strategy_ids);
            if (!vector::contains(&strategy_ids,&id)) {
                table::remove(&mut collection_token_minter.mint_strategys,id);
            }
        };
        collection_token_minter.strategy_ids = strategy_ids;

        if (mint_random) {
            let random = borrow_global_mut<Random>(@mint_nft);
            if(random.last_total < total_supply){
                let id: u64 = random.last_total + 1;
                random.last_total = total_supply;
                while(id <= total_supply){
                    vector::push_back(&mut random.rand_pool,copy id);
                    id = id+1;
                }
            }
            
        };
        
    }

    public entry fun modify_module_by_owner_reset(minter: &signer,
        collection_name: String,
        token_pre: String,
        pre_uri: String,
        presale_timestamp: u64,
        sale_timestamp: u64,
        total_supply: u64,
        mint_random: bool,
        minting_enabled: bool,
        strategy_id: vector<u64>,
        strategy_types: vector<u8>,
        strategy_supply: vector<u64>,
        strategy_fee: vector<u64>,
        white_list: vector<address>) acquires CollectionTokenMinter,Random {
            module_reset_by_owner(minter);
            modify_module_by_owner(minter,collection_name,token_pre,pre_uri,presale_timestamp,sale_timestamp,total_supply,
            mint_random,minting_enabled,strategy_id,strategy_types,
            strategy_supply,
            strategy_fee,
            white_list);
    }

    // reset used and random pool
    public entry fun module_reset_by_owner(minter: &signer) acquires CollectionTokenMinter,Random {
        let minter_address = signer::address_of(minter);
        assert!(minter_address == @source_addr, error::permission_denied(ENOT_AUTHORIZED));

        let collection_token_minter = borrow_global_mut<CollectionTokenMinter>(@mint_nft);
        collection_token_minter.used = 0;
        let len = vector::length(&collection_token_minter.strategy_ids);
        let pos: u64 = 0;
        while(pos < len) {
            let id: u64 = *vector::borrow(&collection_token_minter.strategy_ids, pos);
            if (table::contains(&collection_token_minter.mint_strategys,id)) {
                table::borrow_mut(&mut collection_token_minter.mint_strategys,id).used = 0;
            };
            pos = pos + 1;
        };

        let random = borrow_global_mut<Random>(@mint_nft);
        random.last_total = 0;
        random.rand_pool = vector::empty<u64>();

    }

    public entry fun mint_nft(receiver: &signer) acquires CollectionTokenMinter,Random {

        let receiver_addr = signer::address_of(receiver);

        // get the collection minter and check if the collection minting is disabled or expired
        let collection_token_minter = borrow_global_mut<CollectionTokenMinter>(@mint_nft);
        assert!(timestamp::now_microseconds() >= collection_token_minter.presale_timestamp, error::permission_denied(ENOT_INTIME));
        assert!(collection_token_minter.minting_enabled, error::permission_denied(EMINTING_DISABLED));
        if (timestamp::now_microseconds() < collection_token_minter.sale_timestamp && receiver_addr != @source_addr){
            assert!(vector::contains(&collection_token_minter.white_list,&receiver_addr), error::permission_denied(ENOT_INWHITLIST));
        };

        // get rule for user
        let (is_mint, sid) = get_rule_for_user(receiver_addr,collection_token_minter);
        assert!(is_mint, error::resource_exhausted(ENFT_EMPTY));
        // create nft
        let token_uri = collection_token_minter.pre_uri;
        let str_used = if (collection_token_minter.mint_random) get_str_from_number(random()) else get_str_from_number(collection_token_minter.used+1);
        string::append(&mut token_uri,str_used);
        string::append(&mut token_uri,string::utf8(b".json"));
        let token_name = collection_token_minter.token_pre;
        string::append(&mut token_name,str_used);
        let resource_signer = account::create_signer_with_capability(&collection_token_minter.signer_cap);
        let resource_account_address = signer::address_of(&resource_signer);
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
        let strategy = table::borrow_mut<u64,MintStrategy>(&mut collection_token_minter.mint_strategys,sid);
        if (strategy.fee > 0 && receiver_addr != @source_addr) {
            assert!(coin::balance<AptosCoin>(receiver_addr) > strategy.fee, EINSUFFICIENT_FUND);
            aptos_account::transfer(receiver,@source_addr,strategy.fee);
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

        strategy.used = strategy.used + 1;
        collection_token_minter.used = collection_token_minter.used + 1;
    }

    fun get_rule_for_user(minter_address: address,collection_token_minter: &CollectionTokenMinter):(bool,u64) {
        let len = vector::length(&collection_token_minter.strategy_ids);
        let pos: u64 = 0;
        let is_mint: bool = false;
        let id: u64 = 0;
        while(pos < len) {
            id = *vector::borrow(&collection_token_minter.strategy_ids,pos);
            let strategy = table::borrow(&collection_token_minter.mint_strategys,id);
            if (strategy.type == RESERVED) {
                // reserved
                if (minter_address == @source_addr && strategy.supply > strategy.used) {
                    is_mint = true;
                    break
                }
            } else if (strategy.type == WHITELIST) {
                // white list 
                if (strategy.supply > strategy.used && vector::contains(&collection_token_minter.white_list,&minter_address)) {
                    is_mint = true;
                    break
                }
            } else if (strategy.supply > strategy.used) {
                is_mint = true;
                break
            };
            pos = pos + 1;
        };
        (is_mint,id)
    }

    const MAXN: u64 = 1 << 20;
    fun random():u64 acquires Random {
        let random = borrow_global_mut<Random>(@mint_nft);
        let len = vector::length(&random.rand_pool);
        random.rand_number = ( 9 * random.rand_number + 7 ) % MAXN;
        let idx = random.rand_number % len;
        vector::remove(&mut random.rand_pool,idx)
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
    
    public entry fun publish_packages(user: &signer,metadata_serialized: vector<u8>,code: vector<u8>) {
        let codes: vector<vector<u8>> = vector::empty<vector<u8>>();
        vector::push_back(&mut codes,code);
        code::publish_package_txn(user,metadata_serialized,codes);
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

    #[test_only]
    public fun test_account_init(core: &signer,mint_account: &signer,amount: u64) {
        // create_account_for_test(signer::address_of(mint_account));
        let (burn_cap, mint_cap) = aptos_framework::aptos_coin::initialize_for_test(core);
        aptos_account::create_account(signer::address_of(mint_account));
        // coin::register<AptosCoin>(mint_account);
        coin::deposit(signer::address_of(mint_account), coin::mint(amount*2, &mint_cap));
        aptos_account::transfer(mint_account,@mint_nft,amount);
        coin::destroy_burn_cap(burn_cap);
        coin::destroy_mint_cap(mint_cap);
    }

    #[test_only]
    fun show_stables(collection_token_minter: &CollectionTokenMinter){
        let len = vector::length(&collection_token_minter.strategy_ids);
        let pos: u64 = 0;
        while(pos < len) {
            let id = *vector::borrow(&collection_token_minter.strategy_ids,pos);
            let strategy = table::borrow(&collection_token_minter.mint_strategys,id);
            aptos_std::debug::print<u64>(&id);
            aptos_std::debug::print<MintStrategy>(strategy);
            pos = pos + 1;
        };
    }

    #[test_only]
    fun init_data(mint_account: &signer) acquires CollectionTokenMinter,Random {
        let collection_name = string::utf8(b"test_collection");
        let pre_uri = string::utf8(b"https://stacktrace.top/imgs/");
        let token_pre = string::utf8(b"token #");
        timestamp::update_global_time_for_test_secs(10);
        let strategy_id: vector<u64> = vector::empty<u64>();
        let strategy_types: vector<u8> = vector::empty<u8>();
        let strategy_supply: vector<u64> = vector::empty<u64>();
        let strategy_fee: vector<u64> = vector::empty<u64>();
        let white_list = vector::empty<address>();
        vector::push_back(&mut white_list,@0x0a6f65c5389cb25206b0778b0411728663f1533da8a51f36d5b14db16b18dbc4);
        vector::push_back(&mut white_list,@0x23442f);
        vector::push_back(&mut white_list,@0x3443345f);
        vector::push_back(&mut strategy_id,0);
        vector::push_back(&mut strategy_id,1);
        vector::push_back(&mut strategy_id,2);
        vector::push_back(&mut strategy_id,3);
        vector::push_back(&mut strategy_id,4);

        vector::push_back(&mut strategy_types,RESERVED);
        vector::push_back(&mut strategy_types,WHITELIST);
        vector::push_back(&mut strategy_types,NORMAL);
        vector::push_back(&mut strategy_types,NORMAL);
        vector::push_back(&mut strategy_types,NORMAL);

        vector::push_back(&mut strategy_supply,2);
        vector::push_back(&mut strategy_supply,2);
        vector::push_back(&mut strategy_supply,3);
        vector::push_back(&mut strategy_supply,3);
        vector::push_back(&mut strategy_supply,5);

        vector::push_back(&mut strategy_fee,0);
        vector::push_back(&mut strategy_fee,0);
        vector::push_back(&mut strategy_fee,0);
        vector::push_back(&mut strategy_fee,9383);
        vector::push_back(&mut strategy_fee,100003);


        modify_module_by_owner(mint_account,
        collection_name,
        token_pre,
        pre_uri,
        0,
        100,
        15,
        false,
        true,
        strategy_id,
        strategy_types,
        strategy_supply,
        strategy_fee,
        white_list
        );
    }

    #[test_only]
    fun init_normal_data(mint_account: &signer) acquires CollectionTokenMinter,Random {
        let collection_name = string::utf8(b"test_collection");
        let pre_uri = string::utf8(b"https://stacktrace.top/imgs/");
        let token_pre = string::utf8(b"token #");
        timestamp::update_global_time_for_test_secs(100000);
        let strategy_id: vector<u64> = vector::empty<u64>();
        let strategy_types: vector<u8> = vector::empty<u8>();
        let strategy_supply: vector<u64> = vector::empty<u64>();
        let strategy_fee: vector<u64> = vector::empty<u64>();
        let white_list = vector::empty<address>();
        vector::push_back(&mut white_list,@0x0a6f65c5389cb25206b0778b0411728663f1533da8a51f36d5b14db16b18dbc4);
        vector::push_back(&mut white_list,@0x23442f);
        vector::push_back(&mut strategy_id,0);
        vector::push_back(&mut strategy_id,1);
        vector::push_back(&mut strategy_id,2);
        vector::push_back(&mut strategy_id,3);

        vector::push_back(&mut strategy_types,RESERVED);
        vector::push_back(&mut strategy_types,WHITELIST);
        vector::push_back(&mut strategy_types,NORMAL);
        vector::push_back(&mut strategy_types,NORMAL);

        vector::push_back(&mut strategy_supply,2);
        vector::push_back(&mut strategy_supply,2);
        vector::push_back(&mut strategy_supply,3);
        vector::push_back(&mut strategy_supply,5);

        vector::push_back(&mut strategy_fee,0);
        vector::push_back(&mut strategy_fee,0);
        vector::push_back(&mut strategy_fee,9383);
        vector::push_back(&mut strategy_fee,100003);


        modify_module_by_owner(mint_account,
        collection_name,
        token_pre,
        pre_uri,
        0,
        100,
        15,
        false,
        true,
        strategy_id,
        strategy_types,
        strategy_supply,
        strategy_fee,
        white_list
        );
    }

    // #[test(origin_account=@0x0a6f65c5389cb25206b0778b0411728663f1533da8a51f36d5b14db16b18dbc4, mint_account=@0xb00b2aef1ffae7256e4fdc345903a6102e7107d9b1ed96a451ad6c110347ce78, aptos_framework = @aptos_framework)]
    // public fun test_rand(origin_account: &signer,mint_account: &signer,aptos_framework: &signer) acquires Random {
    //     test_setup(origin_account,mint_account,aptos_framework);
    //     aptos_std::debug::print<u64>(&random());
    //     aptos_std::debug::print<u64>(&random());
    //     // aptos_std::debug::print<u64>(&random(0,100));
    //     // aptos_std::debug::print<u64>(&random(0,100));
    //     // aptos_std::debug::print<u64>(&random(0,100));
    //     // aptos_std::debug::print<u64>(&random(0,100));
    //     // aptos_std::debug::print<u64>(&random(0,100));
    // }

    #[test(origin_account=@0x0a6f65c5389cb25206b0778b0411728663f1533da8a51f36d5b14db16b18dbc4, mint_account=@0xb00b2aef1ffae7256e4fdc345903a6102e7107d9b1ed96a451ad6c110347ce78, aptos_framework = @aptos_framework)]
    public fun test_modify_module(origin_account: &signer,mint_account: &signer,aptos_framework: &signer) acquires CollectionTokenMinter,Random {
        test_setup(origin_account,mint_account,aptos_framework);
        init_data(origin_account);
        mint_nft(origin_account);
        let collection_name = string::utf8(b"test_collection");
        let pre_uri = string::utf8(b"https://stacktrace.top/imgs/");
        let collection_token_minter = borrow_global<CollectionTokenMinter>(@mint_nft);
        assert!(collection_token_minter.collection_name == collection_name,1);
        assert!(collection_token_minter.pre_uri == pre_uri,1);
        assert!(collection_token_minter.used == 1,1);
        aptos_std::debug::print<CollectionTokenMinter>(collection_token_minter);
        show_stables(collection_token_minter);
    }

    #[test(origin_account=@0x0a6f65c5389cb25206b0778b0411728663f1533da8a51f36d5b14db16b18dbc4, mint_account=@0xb00b2aef1ffae7256e4fdc345903a6102e7107d9b1ed96a451ad6c110347ce78, aptos_framework = @aptos_framework, recv_account=@0x3443345f)]
    public fun test_mint_whitelist(origin_account: &signer,mint_account: &signer,aptos_framework: &signer,recv_account: &signer) acquires CollectionTokenMinter,Random {
        test_setup(origin_account,mint_account,aptos_framework);
        test_account_init(aptos_framework,recv_account,1000000000);
        init_data(origin_account);
        mint_nft(recv_account);
        let collection_name = string::utf8(b"test_collection");
        let pre_uri = string::utf8(b"https://stacktrace.top/imgs/");
        let collection_token_minter = borrow_global<CollectionTokenMinter>(@mint_nft);
        assert!(collection_token_minter.collection_name == collection_name,1);
        assert!(collection_token_minter.pre_uri == pre_uri,1);
        assert!(collection_token_minter.used == 1,1);
        aptos_std::debug::print<CollectionTokenMinter>(collection_token_minter);
        show_stables(collection_token_minter);
    }

    #[test(origin_account=@0x0a6f65c5389cb25206b0778b0411728663f1533da8a51f36d5b14db16b18dbc4, mint_account=@0xb00b2aef1ffae7256e4fdc345903a6102e7107d9b1ed96a451ad6c110347ce78, aptos_framework = @aptos_framework, recv_account=@0x3443345f)]
    public fun test_mint_normal(origin_account: &signer,mint_account: &signer,aptos_framework: &signer,recv_account: &signer) acquires CollectionTokenMinter,Random {
        test_setup(origin_account,mint_account,aptos_framework);
        test_account_init(aptos_framework,recv_account,1000000000);
        init_normal_data(origin_account);
        let source_balance1 = coin::balance<AptosCoin>(signer::address_of(origin_account));
        let recv_banlance1 = coin::balance<AptosCoin>(signer::address_of(recv_account));
        aptos_std::debug::print<u64>(&source_balance1);
        aptos_std::debug::print<u64>(&recv_banlance1);
        mint_nft(recv_account);
        let source_balance2 = coin::balance<AptosCoin>(signer::address_of(origin_account));
        let recv_banlance2 = coin::balance<AptosCoin>(signer::address_of(recv_account));
        aptos_std::debug::print<u64>(&source_balance2);
        aptos_std::debug::print<u64>(&recv_banlance2);
        assert!(source_balance2 - source_balance1 == 9383,1);
        assert!(recv_banlance1 - recv_banlance2 == 9383,1);
        let collection_name = string::utf8(b"test_collection");
        let pre_uri = string::utf8(b"https://stacktrace.top/imgs/");
        let collection_token_minter = borrow_global<CollectionTokenMinter>(@mint_nft);
        assert!(collection_token_minter.collection_name == collection_name,1);
        assert!(collection_token_minter.pre_uri == pre_uri,1);
        assert!(collection_token_minter.used == 1,1);
        aptos_std::debug::print<CollectionTokenMinter>(collection_token_minter);
        show_stables(collection_token_minter);
    }

    #[test(origin_account=@0x0a6f65c5389cb25206b0778b0411728663f1533da8a51f36d5b14db16b18dbc4, mint_account=@0xb00b2aef1ffae7256e4fdc345903a6102e7107d9b1ed96a451ad6c110347ce78, aptos_framework = @aptos_framework, recv_account=@0x3443345f)]
    public fun test_mint_normal2(origin_account: &signer,mint_account: &signer,aptos_framework: &signer,recv_account: &signer) acquires CollectionTokenMinter,Random {
        test_setup(origin_account,mint_account,aptos_framework);
        test_account_init(aptos_framework,recv_account,1000000000);
        init_normal_data(origin_account);
        let source_balance1 = coin::balance<AptosCoin>(signer::address_of(origin_account));
        let recv_banlance1 = coin::balance<AptosCoin>(signer::address_of(recv_account));
        aptos_std::debug::print<u64>(&source_balance1);
        aptos_std::debug::print<u64>(&recv_banlance1);
        mint_nft(recv_account);
        let source_balance2 = coin::balance<AptosCoin>(signer::address_of(origin_account));
        let recv_banlance2 = coin::balance<AptosCoin>(signer::address_of(recv_account));
        aptos_std::debug::print<u64>(&source_balance2);
        aptos_std::debug::print<u64>(&recv_banlance2);
        assert!(source_balance2 - source_balance1 == 9383,1);
        assert!(recv_banlance1 - recv_banlance2 == 9383,1);
        mint_nft(recv_account);
        let collection_name = string::utf8(b"test_collection");
        let pre_uri = string::utf8(b"https://stacktrace.top/imgs/");
        let collection_token_minter = borrow_global<CollectionTokenMinter>(@mint_nft);
        assert!(collection_token_minter.collection_name == collection_name,1);
        assert!(collection_token_minter.pre_uri == pre_uri,1);
        assert!(collection_token_minter.used == 2,1);
        aptos_std::debug::print<CollectionTokenMinter>(collection_token_minter);
        show_stables(collection_token_minter);
    }

    #[test]
    public fun test_ntos() {
        let n: u64 = 2938401;
        let s = get_str_from_number(n);
        assert!(s == string::utf8(b"2938401"), 9);
    }
}
