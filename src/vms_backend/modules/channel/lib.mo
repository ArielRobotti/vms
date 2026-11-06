import Types "./types";
import Map "mo:map/Map";
import { phash } "mo:map/Map";
import Array "mo:core/Array";

module {
  public type Channel = Types.Channel;
  type ChannelMap = Types.ChannelMap;
  public type ChannelDataInit = Types.ChannelDataInit;
  public type ChannelEditableData = Types.ChannelEditableData;

  public func initState() : ChannelMap {
    Map.new<Principal, Channel>();
  };

  public func createChannel(map: ChannelMap, caller: Principal, email: Text, init: ChannelDataInit): Channel {
    switch(Map.get(map, phash, caller)) {
      case ( ?channel ) channel;
      case null {
        let newChannel: Channel = {
          init with 
          banner : ?Blob = null;
          content = [];
          extraData = [];
          logo : ?Blob = null;
          owner : Principal = caller;
          followers = [];
          followeds = [];
          tags = [];
          recoveryEmail = email;
          visible = true;
        };
        ignore Map.put(map, phash, caller, newChannel);
        newChannel
      }
    }
  };

  public func getChannel(map: ChannelMap, owner: Principal) : {#Ok: Channel; #Err: Text} {
    switch(Map.get(map, phash, owner)) {
      case null { #Err("Channel Not found")};
      case ( ?channel ) {#Ok(channel)}
    }
  };

  public func editChannel(map: ChannelMap, caller: Principal, data: Types.ChannelEditableData) : {#Ok: Channel; #Err: Text} {
    switch (Map.get(map, phash, caller)) {
      case null {#Err("Channel Not found")};
      case ( ?channel ) {
        let {banner; description; logo; name; tags; visible} = data;
        let channelUpdate = {
          channel with
          name;
          description;
          banner;
          logo;
          tags;
          visible;
        };
        ignore Map.put(map, phash, caller, channelUpdate);
        #Ok(channelUpdate)
      }
    }
  };

  public func channelExist(map: ChannelMap, caller: Principal) : Bool {
    Map.has(map, phash, caller);
  };

  public func addAsset(map: ChannelMap, caller: Principal, id: Int): {#Ok: Int; #Err: Text} {
    switch (Map.get(map, phash, caller)) {
      case null return #Err("Caller does not have an associated channel");
      case ( ?channel ) {
        let contentUpdate = Array.concat<Int>(channel.content, [id]);
        ignore Map.put(map, phash, caller, {channel with content = contentUpdate});
        #Ok(id)
      }
    }
  }

};
