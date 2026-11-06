import Map "mo:map/Map";
import List "mo:core/List";
import SharedTypes "../sharedTypes";

module {

  type UID = SharedTypes.UID;

  public type Comment = {
    msg : Text;
    creator : Principal;
    created_at : Int;
    likes : [Principal];
    dislikes : [Principal];
    subComments : List.List<Comment>;
  };


  public type InteractionBook = Map.Map<UID, MediaInteraction>;

  public type MediaInteraction = {
    comments:  [Comment]
  };
};
