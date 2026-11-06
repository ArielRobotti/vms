// import Prim "mo:prim";
// import Set "mo:map/Set";
// import { phash; ihash; thash } "mo:map/Map";
// import { now } "mo:core/Time";
import Map "mo:map/Map";
import Nat32 "mo:core/Nat32";
import Text "mo:core/Text";
import Nat "mo:core/Nat";
import SharedTypes "../sharedTypes";
import Principal "mo:core/Principal";
import Int "mo:core/Int";
import Array "mo:core/Array";

module {

  public type LocationData = {
    canisterId : Principal;
    internalId : Int;
  };

  public type FileDataInput = {
    name : Text;
    mimeType : Text;
    size : Nat;
    totalChunks : Nat;
    duration : ?Nat; // Audio-Video case
    extraData: SharedTypes.MetadataArray;
    hash : Text; // generado en el frontend mediante sha256
  };

  public type MetadataFile = FileDataInput and {
    owner : Principal;
    createdAt : Int;
    ready : Bool; // TODO ver la forma de pasar a true ante casos de fallo en los que otro usuario pudo subir el mismo archivo
    // extraData : [SharedTypes.MetadataItem];
  };

  public type File = MetadataFile and {
    locationData : LocationData;
  };

  public type BucketStatus = {
    status : { #Stopped; #Stopping; #Running };
    memorySize : Nat;
    availableMemory : Nat;
    fileQty : Nat;
    users : Nat;
    balance : Nat;
  };

  public type StreamingToken = {
    fileId : FileId;
    index : Nat;
  };

  //---------------- Soporte para de-duplicacion de archivos y upload colaborativo ------------------------//

  public type ContentStatus = {
    #RequireUpload : {
      fileId : FileId;
      missingMask : Nat; // Array de bits que representan los chunks faltantes.
    };
    #Done : FileId;
  };

  public type ContentRef = {
    size : Nat;
    refCount : Nat;
    status : ContentStatus;
  };

  public type UploadResponse = {
    #Ok : { bucketId : Principal; status : ContentStatus };
    #FullBucket;
    #Err : Text;
  };

  public type DownloadInfo = {
    name : Text;
    mimeType : Text;
    size : Nat;
    totalChunks : Nat;
  };

  //----------------------------------------------------------------------------

  public type HashFile = Text;
  public type FileId = Int;

  public type ChunkKey = (HashFile, Nat);
  public type AccessKey = (Principal, FileId);

  func hashChunkKey(k : ChunkKey) : Nat32 {
    Map.hashText(k.0 # Nat.toText(k.1));
  };

  func eqChunkKey(a : ChunkKey, b : ChunkKey) : Bool {
    a.0 == b.0 and a.1 == b.1
  };

  func hashAccessKey(k : AccessKey) : Nat32 {
    Map.hashText(Principal.toText(k.0) # Int.toText(k.1));
  };

  func eqAccessKey(a : AccessKey, b : AccessKey) : Bool {
    a.0 == b.0 and a.1 == b.1
  };

  public let khash = (hashChunkKey, eqChunkKey);
  public let ahash = (hashAccessKey, eqAccessKey);

  //------------------- Bucket canister management ------------//

  public type canister_settings = {
    freezing_threshold : ?Nat;
    controllers : ?[Principal];
    memory_allocation : ?Nat;
    compute_allocation : ?Nat;
  };
  public type definite_canister_settings = {
    freezing_threshold : Nat;
    controllers : [Principal];
    memory_allocation : Nat;
    compute_allocation : Nat;
  };

  type StatusResponse = {
    status : { #stopped; #stopping; #running };
    memory_size : Nat;
    cycles : Nat;
    settings : definite_canister_settings;
    idle_cycles_burned_per_day : Nat;
    module_hash : ?[Nat8];
  };

  public type CanisterManager = actor {
    canister_status : shared { canister_id : Principal } -> async StatusResponse;

    delete_canister : shared { canister_id : Principal } -> async ();

    deposit_cycles : shared { canister_id : Principal } -> async ();

    start_canister : shared { canister_id : Principal } -> async ();

    stop_canister : shared { canister_id : Principal } -> async ();

    uninstall_code : shared { canister_id : Principal } -> async ();

    update_settings : shared {
      canister_id : Principal;
      settings : canister_settings;
    } -> async ();
  };

  public func addController(canister_id : Principal, new : Principal) : async () {
    let canisterManager : CanisterManager = actor ("aaaaa-aa");

    let currentControllers = (await canisterManager.canister_status({ canister_id })).settings.controllers;
    let controllers = Array.concat<Principal>(currentControllers, [new]);

    await canisterManager.update_settings({
      canister_id;
      settings = {
        freezing_threshold = null;
        controllers = ?controllers;
        memory_allocation = null;
        compute_allocation = null;
      };
    });
  };

  public func canisterStatus(canister_id: Principal): async StatusResponse {
    let canisterManager : CanisterManager = actor ("aaaaa-aa");
    await canisterManager.canister_status({canister_id})

  };

  public func balance(canister_id : Principal) : async Nat {
    (await canisterStatus(canister_id)).cycles
  }

};
