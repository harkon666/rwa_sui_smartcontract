// Filename: sources/rwa_platform.move
module rwa_project::rwa {
    use sui::package;
    use sui::object::{Self, ID, UID};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext, sender};
    use sui::table::{Self, Table};
    use std::string::{Self, String, utf8};
    use sui::address;
    use std::hash;
    use sui::event;
    use sui::url::{Self, Url};
    use sui::display::{Self, Display};

    // === Error Codes ===
    const E_BRAND_ALREADY_HAS_COLLECTION: u64 = 0;
    const E_NOT_COLLECTION_CREATOR: u64 = 1;
    const E_INVALID_SECRET_CODE: u64 = 2;

    // === One time witness ===
    public struct RWA has drop {}

    // === Events ===

    /// Event saat koleksi baru dibuat.
    public struct CollectionCreated has copy, drop {
        platform_id: ID,
        collection_id: ID,
        brand_address: address,
        collection_name: String,
    }

    /// Event saat NFT berhasil diklaim.
    public struct NftClaimed has copy, drop {
        collection_id: ID,
        nft_id: ID,
        claimer_address: address,
    }
    
    // === Structs ===

    /// NFT yang merepresentasikan aset dunia nyata.
    public struct RwaNft has key, store {
        id: UID,
        name: String,
        description: String,
        image_url: Url,
        creator: address,
    }

    /// Objek koleksi milik satu merek.
    public struct BrandCollection has key, store {
        id: UID,
        name: String,
        description: String,
        creator: address,
        // Kunci: Hash dari kode rahasia. Nilai: Objek NFT.
        unclaimed_nfts: Table<vector<u8>, RwaNft>,
    }

    /// Objek utama platform yang mengatur semua merek.
    public struct Platform has key, store {
        id: UID,
        // Kunci: Alamat merek. Nilai: ID koleksi mereka.
        brand_collections: Table<address, ID>,
    }

    // === event ===
    public struct NftMinted has copy, drop {
        collection_id: ID,
        hashed_secret: vector<u8>,
    }

    // === Functions ===

    /// Inisialisasi platform saat pertama kali deploy.
    fun init(witness: RWA, ctx: &mut TxContext) {
        transfer::share_object(Platform {
            id: object::new(ctx),
            brand_collections: table::new(ctx),
        });

        let keys = vector[
            utf8(b"name"),
            utf8(b"description"),
            utf8(b"image_url"),
            utf8(b"creator"),
        ];

        let values = vector[
            utf8(b"{name}"),
            utf8(b"{description}"),
            utf8(b"{image_url}"),
            utf8(b"{creator}")
        ];

        let publisher = package::claim(witness, ctx);
        let mut display = display::new_with_fields<RwaNft>(&publisher, keys, values, ctx);
        display::update_version(&mut display);

        transfer::public_transfer(publisher, tx_context::sender(ctx));
        transfer::public_transfer(display, tx_context::sender(ctx));
    }

    /// Dipanggil oleh merek untuk membuat satu-satunya koleksi mereka.
    public entry fun create_collection(
        platform: &mut Platform,
        name: vector<u8>,
        description: vector<u8>,
        ctx: &mut TxContext
    ) {
        let brand = sender(ctx);
        // Aturan #1: Pastikan merek ini belum punya koleksi.
        assert!(!table::contains(&platform.brand_collections, brand), E_BRAND_ALREADY_HAS_COLLECTION);

        let collection = BrandCollection {
            id: object::new(ctx),
            name: string::utf8(name),
            description: string::utf8(description),
            creator: brand,
            unclaimed_nfts: table::new(ctx),
        };

        let collection_id = object::id(&collection);
        table::add(&mut platform.brand_collections, brand, collection_id);
        
        event::emit(CollectionCreated {
            platform_id: object::id(platform),
            collection_id,
            brand_address: brand,
            collection_name: collection.name,
        });

        transfer::share_object(collection);
    }

    /// Dipanggil oleh merek untuk me-mint NFT baru ke dalam koleksinya.
    public entry fun mint_nft(
        collection: &mut BrandCollection,
        hashed_secret: vector<u8>, // PENTING: Merek mengirim HASH dari kode, bukan kode mentah.
        name: vector<u8>,
        description: vector<u8>,
        url: vector<u8>,
        ctx: &mut TxContext
    ) {
        // Hanya pembuat koleksi yang boleh me-mint.
        assert!(collection.creator == sender(ctx), E_NOT_COLLECTION_CREATOR);
        
        let nft = RwaNft {
            id: object::new(ctx),
            name: string::utf8(name),
            description: string::utf8(description),
            image_url: url::new_unsafe_from_bytes(url),
            creator: sender(ctx),
        };

        table::add(&mut collection.unclaimed_nfts, hashed_secret, nft);
        event::emit(NftMinted {
          collection_id: object::id(collection),
          hashed_secret
        });
    }

    /// Dipanggil oleh user untuk mengklaim NFT dengan kode rahasia.
    public entry fun claim_nft_with_code(
        collection: &mut BrandCollection,
        secret_code: vector<u8>, // User mengirim kode mentah.
        ctx: &mut TxContext
    ) {
        // Kontrak akan melakukan hashing di dalam untuk mencocokkan.
        // let hashed_secret = hash::sha2_256(secret_code);

        // Aturan #2: Pastikan kode rahasia ini valid dan ada NFT yang terkait.
        assert!(table::contains(&collection.unclaimed_nfts, secret_code), E_INVALID_SECRET_CODE);

        let nft = table::remove(&mut collection.unclaimed_nfts, secret_code);
        let claimer = sender(ctx);
        
        event::emit(NftClaimed {
            collection_id: object::id(collection),
            nft_id: object::id(&nft),
            claimer_address: claimer,
        });
        
        transfer::public_transfer(nft, claimer);
    }
}