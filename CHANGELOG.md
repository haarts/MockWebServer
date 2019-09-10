# Changelog

## 4.1.1 - Sept 10, 2019
- Added compatibility with Dart 2.5.0

## 4.1.0 - Aug 04, 2019
- Added `defaultResponse`

## 4.0.0 - Dec 06, 2018
- Changed `takeRequest()` to be FIFO like Square's implementation

## Breaking
- All your tests need to be updated to use `takeRequest()` according to above

## 3.0.0 - Nov 27, 2018
### Changed
- Updated code to support Dart 2
- Added SDK constraint to Dart 2

## Breaking
- Dart 2 is required

## 2.1.0 - Oct 21, 2017
### Changed
- Using a MockWebServer class to return the stored requests
- Loading the body of stored requests to facilitate validation
- Using a queue

## 2.0.1 - Oct 15, 2017
### Changed
- Better request count management to avoid external modifications

## 2.0.0 - Oct 15, 2017
### Breaking
- Support for TLS now receives the cert config for better flexibility
and also to remove `resource` from the dependencies

## 1.3.0 - Oct 11, 2017
### Added
- Support for TLS
- Support to set the Inet Address type to IPv6, default value is IPv4

### Changed
- Better property handling

## 1.2.0 - Aug 25, 2017
### Added
- Support for async dispatcher

## 1.1.0 - Aug 20, 2017
### Added
- Request count
- Comprehensive documentation

### Fixed
- Bug when delaying would be ignored if a Dispatcher was set

## 1.0.0 - Aug 17, 2017
### Added
- All the basic functionality
