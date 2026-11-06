import SharedTypes "../sharedTypes";
import Types "types";
import List "mo:core/List";


module {

  public type Comment = Types.Comment; 

  func pushBack<T>(input : T, list : List.List<T>) : List.List<T> {
    switch list {
      case null {
        return ?(input, null);
      };
      case (?(head, tail)) {
        return ?(head, pushBack(input, tail));
      };
    };
  };

  public func push(list : List.List<Comment>, input : Comment, path : [Int]) : List.List<Comment> {
    if (path.size() == 0) {
      return pushBack<Comment>(input, list) // Condicion de salida de recursividad
    } else {
      var commentsResult = List.nil<Comment>();

      for (comment in List.toIter(List.reverse(list))) {
        if (comment.created_at == path[0]) {
          let subPath = Array.subArray<Int>(path, 1, path.size() - 1 : Nat);
          let subComments = push(comment.subComments, input, subPath); // Llamada recursiva
          commentsResult := List.push<Comment>({ comment with subComments }, commentsResult);
        } else {
          commentsResult := List.push<Comment>(comment, commentsResult);
        };
      };
      return commentsResult;
    };
  };

  public func pushLike(list : List.List<Comment>, input : Comment, path : [Int]) : List.List<Comment> {
    if (path.size() == 0) {
      return pushBack<Comment>(input, list) // Condicion de salida de recursividad
    } else {
      var commentsResult = List.nil<Comment>();

      for (comment in List.toIter(List.reverse(list))) {
        if (comment.created_at == path[0]) {
          let subPath = Array.subArray<Int>(path, 1, path.size() - 1 : Nat);
          let subComments = push(comment.subComments, input, subPath); // Llamada recursiva
          commentsResult := List.push<Comment>({ comment with subComments }, commentsResult);
        } else {
          commentsResult := List.push<Comment>(comment, commentsResult);
        };
      };
      return commentsResult;
    };
  };

  public func getComment(list : List.List<Comment>, path : [Int]): ?Comment {
    if (path.size() == 0) { return null };

    for(comment in List.toIter(List.reverse(list))) {
      if(comment.created_at == path[0]) {
        if (path.size() == 1){
          return ?comment;
        } else {
          return getComment(comment.subComments, Array.subArray<Int>(path, 1, path.size() -1: Nat))
        }
      }
    };
    return null
  };

};