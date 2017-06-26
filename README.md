RestEngine (old name: APIUtils)
==========
Swift framework for easy access to rest apis

This Framwork will wrap all the incombences of rest api access with a Functional Reactive Programming interface (RxSwift). It will take care of making network requests, handling the cache, showing the progress bars, and even handle disconnection and reconnection to the internet.

## Usage

Suppose you have an api at url 
http://api.someserver.com/users 
when you call that api with the get method you get a json array of User objects. Something like:
```json
[
  {
    "name":"John",
    "id":1
  },
  {
    "name":"Bob",
    "id":2
  }
]
```
Then you can prepare the mapping struct:

```swift
import Alamofire
import APIUtils
import Argo
import Curry
import Foundation
import Ogra
import Runes

struct User:Arrayable {
	let id:Int
	let name:String
	
  // this is used by the library to convert a User to a json object
  func encode() -> JSON {
		return JSON.object([
			"id":id.encode(),
			"name":name.encode()
			])
	}
  // this is used by the library to convert a json object into an User
	static func decode(_ j: JSON) -> Decoded<User> {
		return curry(User.init)
			<^> j <| "id"
			<*> j <| "name"
	}
	
  // this is needed for some limitation of the swift generic mechanics
	static func decodeMeArray(_ j:[Any]) -> Decoded<[User]> {
		return Argo.decode(j)
	}
}
```
and the api class:
```swift
// here you define the api access class
// this api take nothing as input (EmptyIn)
// and returns an array (ArrayApi) of users (User)
final class GetUsers:RestApiBase<EmptyIn,User>,ArrayApi
{
	var url="http://api.someserver.com/users"
	let method = Alamofire.HTTPMethod.get
  // here you define how you want this call to be cached, in this case we accept a cache 24 hours old. 
  // we will try to get updated values if possible, unless the cache is really fresh (<2.5% of the expiry age)
	var cachability:Cachability {return .cache(expiry:.hours(24))}
}
```
Later, when you want to retrieve the users you use:
```swift
GetUsers(input:EmptyIn(),progress:self.progress).rxArray()
```
which will give you an Observable<[User]>. That self.progress is an optional progressbar in the viewcontroller, that will show the uploading/downloading progress.

## Installation
The library is not yet available via Cocoapods or Carthage, my apologies for that. For the time being you will have to include it in your workspace, and provide this dependencies:
```
github "ReactiveX/RxSwift"
github "Alamofire/Alamofire"
github "tristanhimmelman/AlamofireObjectMapper"
github "thoughtbot/Argo"
github "thoughtbot/Curry"
github "thoughtbot/Runes"
github "Marxon13/M13ProgressSuite"
github "Hearst-DD/ObjectMapper"
github "edwardaux/Ogra"
github "pinterest/PINCache"
github "ashleymills/Reachability.swift"
github "hariseldon78/DataVisualization"
```
