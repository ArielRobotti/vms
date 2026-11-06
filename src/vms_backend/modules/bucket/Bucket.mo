import Prim "mo:prim";
import Map "mo:map/Map";
import Set "mo:map/Set";
import { phash; ihash; thash } "mo:map/Map";
import Text "mo:core/Text";
import Nat "mo:core/Nat";
import { now } "mo:core/Time";
import Principal "mo:core/Principal";
import Int "mo:core/Int";
import Types "types";
import { ahash; khash } "types";
// import { print } "mo:core/Debug";
import Blob "mo:core/Blob";

//////////////// Bucket actor class ////////////

shared ({ caller = DEPLOYER }) persistent actor class Bucket(admin : Principal) = this {

  //------------------- Types -------------------//

  public type AccessKey = Types.AccessKey;
  public type FileId = Types.FileId;
  public type MetadataFile = Types.MetadataFile;
  public type FileDataInput = Types.FileDataInput;
  public type HashFile = Types.HashFile;
  public type ContentRef = Types.ContentRef;
  public type ChunkKey = Types.ChunkKey;
  public type BucketStatus = Types.BucketStatus;
  public type UploadResponse = Types.UploadResponse;
  public type StreamingToken = Types.StreamingToken;

  type Http_request = {
    url : Text; 
    method : Text; 
    body : Blob; 
    headers : [(Text, Text)];
  };

  type Http_response = {
    status_code : Nat16;
    headers : [(Text, Text)];
    body : Blob;
    streaming_strategy : ?{
      #Callback : {
        token : StreamingToken;
        callback : shared query StreamingToken -> async {
          body : Blob;
          token : ?StreamingToken;
        };
      };
    };
  };

  //---------------------------------------------//

  let _status = {
    var status = #Running;
    var memorySize = 0;
    var fileQty = 0;
    var users = 0;
    var admins = [DEPLOYER, admin];
  };

  let _config = {
    var maxStorageCapacity = 300 * 1024 * 1024 * 1024;
    var maxChunkSize = 1572864;
    minCyclesThreshold = 0;
  };

  //------------------------------- Access policies ------------------------------//

  let blackList = Set.new<Principal>();
  let accessSet = Set.new<AccessKey>(); // AccessKey = (Principal, FileId). Si existe, el principal tiene acceso al FileId

  //-------------------------------- Data Storage --------------------------------//

  let metadataMap = Map.new<FileId, MetadataFile>();
  let referenceCounterMap = Map.new<HashFile, ContentRef>();
  let chunks = Map.new<ChunkKey, Blob>(); // ChunkKey = (HashFile, Nat). Hash del archivo, Text, + indice del chunk

  //------------------------------------------------------------------------------//

  public shared ({ caller }) func status() : async BucketStatus {
    assert (isAdmin(caller));
    {
      status = _status.status;
      memorySize = _status.memorySize;
      availableMemory = _config.maxStorageCapacity - _status.memorySize;
      fileQty = _status.fileQty;
      users = _status.users;
      balance = Prim.cyclesBalance();
    };
  };

  //-------------------------- Private functions ---------------------------------//

  func isAdmin(p : Principal) : Bool {
    for (a in _status.admins.vals()) { if (a == p) return true };
    false;
  };


  func bucketId() : Principal {
    Principal.fromActor(this);
  };

  public shared ({ caller }) func requestStorageFor(metadata : FileDataInput, owner : Principal) : async UploadResponse {
    // accion permitida solo al canister backend
    assert (isAdmin(caller));
    if (Set.has<Principal>(blackList, phash, owner)) {
      return #Err("User in blacklist");
    };

    let fileId = now();
    
    // Otorgamos permiso de acceso al usuario
    ignore Set.put<AccessKey>(accessSet, ahash, (owner, fileId));

    // Vemos si el contenido que genera el hash proporcionado por el usuario ya esta alojado o subiendose en el bucket
    switch (Map.get<HashFile, ContentRef>(referenceCounterMap, thash, metadata.hash)) {
      case null {
        // ver si el bucket tiene espacio
        if (_config.maxStorageCapacity - _status.memorySize : Nat < metadata.size) {
          return #FullBucket;
        };
        let status = #RequireUpload({
          missingMask = 2 ** metadata.totalChunks - 1 : Nat;
          fileId;
        });
        ignore Map.put<HashFile, ContentRef>(
          referenceCounterMap,
          thash,
          metadata.hash,
          { size = metadata.size; refCount = 1; status },
        );
        // let maxChunkSize = _config.maxChunkSize;
        ignore Map.put<FileId, MetadataFile>(
          metadataMap,
          ihash,
          fileId,
          {
            metadata with
            owner;
            ready = false;
            createdAt = now();
          },
        );
        return #Ok({ bucketId = bucketId(); status });
      };
      case (?fileReference) {
        // Ya existe el contenido en el bucket asi que solo incrementamos el contador de referencias
        // Y devolvemos el estado de dicho contenido para ver si el usuario puede aportar algun chunk faltante
        if (fileReference.size != metadata.size) {
          ignore Set.remove<AccessKey>(accessSet, ahash, (owner, fileId));
          return #Err("Unexpecter event: file hash collision");
        };
        ignore Map.put<HashFile, ContentRef>(
          referenceCounterMap,
          thash,
          metadata.hash,
          { fileReference with refCount = fileReference.refCount + 1 },
        );
        // let maxChunkSize = fileReference.chunkSize;

        switch (fileReference.status) {
          case (#Done(_)) {
            ignore Map.put<FileId, MetadataFile>(metadataMap, ihash, fileId, { metadata with owner; ready = true; createdAt = now() });
            return #Ok({ bucketId = bucketId(); status = #Done(fileId) });
          };
          case (#RequireUpload(data)) {
            ignore Map.put<FileId, MetadataFile>(metadataMap, ihash, fileId, { metadata with owner; ready = false; createdAt = now() });
            return #Ok({
              bucketId = bucketId();
              status = #RequireUpload({ data with fileId });
            });
          };
        };
      };
    };
  };

  public shared ({ caller }) func putChunk({
    fileId : Int;
    index : Nat;
    chunk : Blob;
  }) : async UploadResponse {
    if (not Set.has<AccessKey>(accessSet, ahash, (caller, fileId))) {
      return #Err("Denied access");
    };
    switch (Map.get<FileId, MetadataFile>(metadataMap, ihash, fileId)) {
      case null { return #Err("Unexpected error: fileId not found") };
      case (?metadata) {

        if (index >= metadata.totalChunks) { return #Err("Index out of range") };

        switch (Map.get<HashFile, ContentRef>(referenceCounterMap, thash, metadata.hash)) {
          case null {
            return #Err("Unexpected error: metadata.hash not found");
          };
          case (?contentRef) {
            switch (contentRef.status) {
              case (#Done(id)) return (#Ok({ bucketId = bucketId(); status = #Done(id) }));
              case (#RequireUpload(state)) {
                let weight = 2 ** index;
                // ¿Ya tenemos este chunk? (Bit es 0)
                if ((state.missingMask / weight) % 2 == 0) {
                  return #Ok({
                    bucketId = bucketId();
                    status = #RequireUpload(state);
                  });
                } else {
                  // Guardamos el chunk
                  ignore Map.put<ChunkKey, Blob>(chunks, khash, (metadata.hash, index), chunk);
                  _status.memorySize += chunk.size();
                  let newMask = state.missingMask - weight : Nat;
                  let updatedRef : ContentRef = if (newMask == 0) {
                    _status.fileQty += 1;
                    ignore Map.put<FileId, MetadataFile>(metadataMap, ihash, fileId, { metadata with ready = true });
                    {
                      contentRef with status = #Done(fileId)
                    };
                  } else {
                    {
                      contentRef with status = #RequireUpload({
                        fileId;
                        missingMask = newMask;
                      })
                    };
                  };
                  ignore Map.put<HashFile, ContentRef>(referenceCounterMap, thash, metadata.hash, updatedRef);
                  return #Ok({
                    bucketId = bucketId();
                    status = updatedRef.status;
                  });
                };
              };
            };
          };
        };
      };
    };
  };

  public query func isFileReady(id: Int) : async Bool {
    switch (Map.get<FileId, MetadataFile>(metadataMap, ihash, id)){
        case ( ?file ) file.ready;
        case null false
    }
  };

  //------------------ http request -----------------------//

  func getRange(headers : [(Text, Text)]) : ?Nat {
    for ((k, v) in headers.vals()) {
      if (Text.toLower(k) == "range") {
        let parts = Text.split(v, #char '=');
        ignore parts.next();
        let val = parts.next();
        switch val {
          case (?t) {
            let n = Text.trimEnd(t, #text "-");
            return Nat.fromText(n);
          };
          case null return null;
        };
      };
    };
    null;
  };

  public query func streaming_callback(token : StreamingToken) : async {
    body : Blob;
    token : ?StreamingToken;
  } {

    switch (Map.get<FileId, MetadataFile>(metadataMap, ihash, token.fileId)) {

      case null {
        return {
          body = Blob.fromArray([]);
          token = null;
        };
      };

      case (?meta) {

        if (token.index >= meta.totalChunks) {
          return {
            body = Blob.fromArray([]);
            token = null;
          };
        };

        switch (Map.get<ChunkKey, Blob>(chunks, khash, (meta.hash, token.index))) {

          case null {
            return {
              body = Blob.fromArray([]);
              token = null;
            };
          };

          case (?chunk) {

            let nextToken = if (token.index + 1 >= meta.totalChunks) null else ?{
              fileId = token.fileId;
              index = token.index + 1;
            };

            return {
              body = chunk;
              token = nextToken;
            };
          };
        };
      };
    };
  };

  public query func http_request(req : Http_request) : async Http_response {
    // Manejo de preflight CORS
    if (req.method == "OPTIONS") {
      return {
        status_code = 204;
        headers = [
          ("Access-Control-Allow-Origin", "*"),
          ("Access-Control-Allow-Methods", "GET, HEAD, OPTIONS"),
          ("Access-Control-Allow-Headers", "*"),
          ("Cross-Origin-Resource-Policy", "cross-origin"),
          ("Cross-Origin-Embedder-Policy", "credentialless"),
          ("Content-Security-Policy", "default-src * data: blob: 'unsafe-inline' 'unsafe-eval'"),
        ];
        body = Blob.fromArray([]);
        streaming_strategy = null;
      };
    };

    let urlParts = Text.split(req.url, #char '?');
    let path = switch (urlParts.next()) {
      case (?p) p;
      case null "";
    };

    // --- CASE 1: VISTA PREVIA (LANDING PAGE HTML) ---
    if (Text.startsWith(path, #text "/v/")) {
      let idText = Text.trimStart(path, #text "/v/");
      let fileId = switch (Int.fromText(idText)) {
        case (?id) id;
        case null { return response400() };
      };

      switch (Map.get<FileId, MetadataFile>(metadataMap, ihash, fileId)) {
        case null { return response404() };
        case (?metadata) {
          let canisterId = Principal.toText(Principal.fromActor(this));
          let rawUrl = "https://" # canisterId # ".raw.icp0.io";
          let thumbUrl = rawUrl # "/thumb/" # idText;
          let videoUrl = rawUrl # "/video/" # idText;
          
          // Logo naranja de Vaultic para el Favicon (SVG Base64)
          let logoFavicon = "data:image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHdpZHRoPSIxMjAiIGhlaWdodD0iMTIwIiB2aWV3Qm94PSIwIDAgMTIwIDEyMCI+PHBhdGggZD0iTTMwIDIwbDYwIDAgMTUgMjZ2NDlsLTE1IDI2LTQwIDAtMTUtMjZ2LTQ5bDE1LTI2eiIgZmlsbD0iIzAwMCIvPjxwYXRoIGQ9Ik00NSA0NWwzMCAxNS0zMCAxNSIgZmlsbD0iI0ZGOTgwMCIvPjxwYXRoIGQ9Ik04MiAzNWM0IDEwIDQgMjAgMCAzME04OCA4NWM1LTExIDUtMjIgMC0zMyIgc3Ryb2tlPSIjRkY5ODAwIiBzdHJva2Utd2lkdGg9IjUiIGZpbGw9Im5vbmUiIHN0cm9rZS1saW5lY2FwPSJyb3VuZCIvPjwvc3ZnPg==";

          let html = "<html><head>" #
          "<title>" # metadata.name # " | Vaultic</title>" #
          "<link rel='icon' href='" # logoFavicon # "' />" #
          
          // Open Graph (WhatsApp, Facebook, Telegram)
          "<meta property='og:title' content='" # metadata.name # " | Vaultic' />" #
          "<meta property='og:description' content='Vaultic Mediastream | Decentralized multimedia storage over the Internet Computer Protocol' />" #
          "<meta property='og:type' content='video.other' />" #
          "<meta property='og:image' content='" # thumbUrl # "' />" #
          "<meta property='og:image:width' content='320' />" #
          "<meta property='og:image:height' content='180' />" #
          "<meta property='og:video' content='" # videoUrl # "' />" #
          "<meta property='og:video:secure_url' content='" # videoUrl # "' />" #
          "<meta property='og:video:type' content='video/mp4' />" #
          "<meta property='og:video:width' content='1280' />" #
          "<meta property='og:video:height' content='720' />" #

          // Twitter / X Cards
          "<meta name='twitter:card' content='player' />" #
          "<meta name='twitter:title' content='" # metadata.name # " | Vaultic' />" #
          "<meta name='twitter:player' content='" # rawUrl # "/v/" # idText # "' />" #
          "<meta name='twitter:player:width' content='1280' />" #
          "<meta name='twitter:player:height' content='720' />" #
          "<meta name='twitter:image' content='" # thumbUrl # "' />" #
          "<meta name='twitter:player:stream' content='" # videoUrl # "' />" #
          "<meta name='twitter:player:stream:content_type' content='video/mp4' />" #

          "<style>body{margin:0;background:#000;display:flex;align-items:center;justify-content:center;height:100vh;}video{max-width:100%;max-height:100%;}</style>" #
          "</head><body>" #
          // playsinline es vital para que no se abra en pantalla completa forzada en iPhone
          "<video src='/video/" # idText # "' controls autoplay playsinline style='width:100%;'></video>" #
          "</body></html>";

          return {
            status_code = 200;
            headers = [
                ("Content-Type", "text/html; charset=utf-8"), 
                ("Access-Control-Allow-Origin", "*")
            ];
            body = Text.encodeUtf8(html);
            streaming_strategy = null;
          };
        };
      };
    };

    // --- CASE 2: SERVIR EL THUMBNAIL BLOB ---
    if (Text.startsWith(path, #text "/thumb/")) {
      let idText = Text.trimStart(path, #text "/thumb/");
      let fileId = switch (Int.fromText(idText)) {
        case (?id) id;
        case null { return response400() };
      };

      switch (Map.get<FileId, MetadataFile>(metadataMap, ihash, fileId)) {
        case null { return response404() };
        case (?metadata) {
          var foundBlob : ?Blob = null;
          for ((key, value) in metadata.extraData.vals()) {
            if (key == "thumbnail_blob") {
              switch (value) {
                case (#Blob b) { foundBlob := ?b };
                case (_) {};
              };
            };
          };

          switch (foundBlob) {
            case null { return response404() };
            case (?imageBytes) {
              return {
                status_code = 200;
                headers = [
                  ("Content-Type", "image/jpeg"),
                  ("Cache-Control", "public, max-age=31536000, immutable"),
                  ("Access-Control-Allow-Origin", "*"),
                  ("Content-Length", Nat.toText(imageBytes.size()))
                ];
                body = imageBytes;
                streaming_strategy = null;
              };
            };
          };
        };
      };
    };

    // --- CASE 3: BINARIO DE VIDEO (TU LÓGICA ORIGINAL) ---
    if (Text.startsWith(path, #text "/video/")) {
      let idText = Text.trimStart(path, #text "/video/");
      let fileId = switch (Int.fromText(idText)) {
        case (?id) id;
        case null { return response400() };
      };

      switch (Map.get<FileId, MetadataFile>(metadataMap, ihash, fileId)) {
        case null { return response404() };
        case (?metadata) {
          let rangeStart = getRange(req.headers);
          let offset = switch (rangeStart) { case null 0; case (?v) v; };
          let startIndex = offset / _config.maxChunkSize;
          let chunkStart = startIndex * _config.maxChunkSize;
          let chunkEnd = Nat.min(chunkStart + _config.maxChunkSize - 1, metadata.size - 1);

          if (offset >= metadata.size) {
            return {
              status_code = 416;
              headers = [("Content-Range", "bytes */" # Nat.toText(metadata.size))];
              body = Blob.fromArray([]);
              streaming_strategy = null;
            };
          };

          switch (Map.get(chunks, khash, (metadata.hash, startIndex))) {
            case null { return response404() };
            case (?chunk) {
              return {
                status_code = if (rangeStart == null) 200 else 206;
                headers = [
                  ("Content-Type", metadata.mimeType),
                  ("Accept-Ranges", "bytes"),
                  ("Content-Range", "bytes " # Nat.toText(chunkStart) # "-" # Nat.toText(chunkEnd) # "/" # Nat.toText(metadata.size)),
                  ("Cache-Control", "public, max-age=31536000, immutable"),
                  ("Access-Control-Allow-Origin", "*"),
                  ("Access-Control-Allow-Methods", "GET, HEAD, OPTIONS"),
                  ("Access-Control-Allow-Headers", "*"),
                  ("Cross-Origin-Embedder-Policy", "credentialless"),
                  ("Content-Security-Policy", "default-src * data: blob: 'unsafe-inline' 'unsafe-eval'"),
                ];
                body = chunk;
                streaming_strategy = ?#Callback({
                  token = { fileId; index = startIndex + 1; };
                  callback = streaming_callback;
                });
              };
            };
          };
        };
      };
    };

    return response404();
  };

  // Helpers para limpieza de código
  func response400() : Http_response {
    { status_code = 400; headers = [("Access-Control-Allow-Origin", "*")]; body = Blob.fromArray([]); streaming_strategy = null; }
  };

  func response404() : Http_response {
    { status_code = 404; headers = [("Access-Control-Allow-Origin", "*")]; body = Blob.fromArray([]); streaming_strategy = null; }
  };

  //-------------------------------------------------------//

  public shared query ({ caller }) func getFileMetadata(fileId : FileId) : async {
    #Ok : MetadataFile;
    #Err : Text;
  } {

    // if (not Set.has<AccessKey>(accessSet, ahash, (caller, fileId))) {
    //   return #Err("Denied access");
    // };
    switch (Map.get<FileId, MetadataFile>(metadataMap, ihash, fileId)) {
      case null { #Err("Metadata not found") };
      case (?metadata) { #Ok(metadata) };
    };
  };

  public shared query ({ caller }) func getChunk({ fileId : Int; index : Nat }) : async {
    #Ok : Blob;
    #Err : Text;
  } {
    // if (not Set.has<AccessKey>(accessSet, ahash, (caller, fileId))) {
    //   return #Err("Denied access");
    // };
    switch (Map.get<FileId, MetadataFile>(metadataMap, ihash, fileId)) {
      case null { #Err("Unexpected error: fileId not found") };
      case (?metadata) {
        switch (Map.get<ChunkKey, Blob>(chunks, khash, (metadata.hash, index))) {
          case null { #Err("Chunk not found") };
          case (?chunk) { #Ok(chunk) };
        };
      };
    };
  };

  public shared ({ caller }) func deleteFile(fileId : Int) : async {
    #Ok;
    #Err : Text;
  } {
    let metadata = switch (Map.get<FileId, MetadataFile>(metadataMap, ihash, fileId)) {
      case (?m) m;
      case (null) return #Err("File not found");
    };
    if (not (caller == metadata.owner)) {
      return #Err("Caller is not file owner");
    };
    switch (Map.get<HashFile, ContentRef>(referenceCounterMap, thash, metadata.hash)) {
      case null { return #Err("Error file reference") };
      case (?ref) {
        if (ref.refCount > 1) {
          ignore Map.put<HashFile, ContentRef>(
            referenceCounterMap,
            thash,
            metadata.hash,
            { ref with refCount = ref.refCount - 1 },
          );
        } else {

          // Ya no hay mas referencias que la actual, borrar todos los chunks físicos
          var i = 0;
          while (i < metadata.totalChunks) {
            let chunkDeleted = Map.remove<ChunkKey, Blob>(chunks, khash, (metadata.hash, i));
            switch chunkDeleted {
              case (?chunk) { _status.memorySize -= chunk.size()};
              
              case null {};
            };
            i += 1;
          };
          // B. Borrar la referencia de contenido
          _status.fileQty -= 1;
          ignore Map.remove<HashFile, ContentRef>(referenceCounterMap, thash, metadata.hash);
        };
      };
    };
    //  Limpieza de metadatos y accesos del usuario actual
    ignore Map.remove<FileId, MetadataFile>(metadataMap, ihash, fileId);
    ignore Set.remove<AccessKey>(accessSet, ahash, (caller, fileId));
    return #Ok;
  };
};
