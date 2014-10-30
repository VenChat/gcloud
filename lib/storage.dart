// Copyright (c) 2014, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// This library provides access to Google Cloud Storage.
///
/// Google Cloud Storage is an object store for binary objects. Each
/// object has a set of metadata attached to it. For more information on
/// Google Cloud Sorage see https://developers.google.com/storage/.
///
/// There are two main concepts in Google Cloud Storage: Buckets and Objects.
/// A bucket is a container for objects and objects are the actual binary
/// objects.
///
/// The API has two main classes for dealing with buckets and objects.
///
/// The class `Storage` is the main API class providing access to working
/// with buckets. This is the 'bucket service' interface.
///
/// The class `Bucket` provide access to working with objcts in a specific
/// bucket. This is the 'object service' interface.
///
/// Both buckets have objects, have names. The bucket namespace is flat and
/// global across all projects. This means that a bucket is always
/// addressable using its name without requiring further context.
///
/// Within buckets the object namespace is also flat. Object are *not*
/// organized hierachical. However, as object names allow the slash `/`
/// character this is often used to simulate a hierachical structure
/// based on common prefixes.
///
/// This package uses relative and absolute names to refer to objects. A
/// relative name is just the object name within a bucket, and requires the
/// context of a bucket to be used. A relative name just looks like this:
///
///     object_name
///
/// An absolute name includes the bucket name and uses the `gs://` prefix
/// also used by the `gsutil` tool. An absolute name looks like this.
///
///     gs://bucket_name/object_name
///
/// In most cases relative names are used. Absolute names are typically
/// only used for operations involving objects in different buckets.
///
/// For most of the APIs in ths library which take instances of other classes
/// from this library it is the assumption that the actual implementations
/// provided here are used.
library gcloud.storage;

import 'dart:async';
import 'dart:collection' show UnmodifiableListView;

import 'package:http/http.dart' as http;

import 'package:crypto/crypto.dart' as crypto;
import 'package:googleapis/storage/v1.dart' as storage;
import 'package:googleapis/common/common.dart' as common;

import 'common.dart';
export 'common.dart';

part 'src/storage_impl.dart';


/// An ACL (Access Control List) describes access rights to buckets and
/// objects.
///
/// An ACL is a prioritized sequence of access control specifications,
/// which individually prevent or grant access.
/// The access controls are described by [AclEntry] objects.
class Acl {
  final _entries;

  /// The entries in the ACL.
  List<AclEntry> get entries => new UnmodifiableListView<AclEntry>(_entries);

  /// Create a new ACL with a list of ACL entries.
  Acl(Iterable<AclEntry> entries) : _entries = new List.from(entries);

  List<storage.BucketAccessControl> _toBucketAccessControlList() {
    return _entries.map((entry) => entry._toBucketAccessControl()).toList();
  }

  List<storage.ObjectAccessControl> _toObjectAccessControlList() {
    return _entries.map((entry) => entry._toObjectAccessControl()).toList();
  }
}

/// An ACL entry specifies that an entity has a specific access permission.
///
/// A permission grants a specific permission to the entity.
class AclEntry {
  final AclScope scope;
  final AclPermission permission;

  AclEntry(this.scope, this.permission);

  storage.BucketAccessControl _toBucketAccessControl() {
    var acl = new storage.BucketAccessControl();
    acl.entity = scope._storageEntity;
    acl.role = permission._storageBucketRole;
    return acl;
  }

  storage.ObjectAccessControl _toObjectAccessControl() {
    var acl = new storage.ObjectAccessControl();
    acl.entity = scope._storageEntity;
    acl.role = permission._storageObjectRole;
    return acl;
  }
}

/// An ACL scope specifies an entity for which a permission applies.
///
/// A scope can be one of:
///
///   * Google Storage ID
///   * Google account email address
///   * Google group email address
///   * Google Apps domain
///   * Special identifier for all Google account holders
///   * Special identifier for all users
///
/// See https://cloud.google.com/storage/docs/accesscontrol for more details.
abstract class AclScope {
  /// ACL type for scope representing a Google Storage id.
  static const int _TYPE_STORAGE_ID = 0;

  /// ACL type for scope representing an account holder.
  static const int _TYPE_ACCOUNT = 1;

  /// ACL type for scope representing a group.
  static const int _TYPE_GROUP = 2;

  /// ACL type for scope representing a domain.
  static const int _TYPE_DOMAIN = 3;

  /// ACL type for scope representing all authenticated users.
  static const int _TYPE_ALL_AUTHENTICATED = 4;

  /// ACL type for scope representing all users.
  static const int _TYPE_ALL_USERS = 5;

  /// The id of the actual entity this ACL scope represents. The actual values
  /// are set in the different subclasses.
  final String _id;

  /// The type of this acope this ACL scope represents.
  final int _type;

  /// ACL scope for all authenticated users.
  static const allAuthenticated = const AllAuthenticatedScope();

  /// ACL scope for all users.
  static const allUsers = const AllUsersScope();

  const AclScope._(this._type, this._id);

  String get _storageEntity {
    switch (_type) {
      case _TYPE_STORAGE_ID:
        return 'user-$_id';
      case _TYPE_ACCOUNT:
        return 'user-$_id';
      case _TYPE_GROUP:
        return 'group-$_id';
      case _TYPE_DOMAIN:
        return 'domain-$_id';
      case _TYPE_ALL_AUTHENTICATED:
        return 'allAuthenticatedUsers';
      case _TYPE_ALL_USERS:
        return 'allUsers';
      default:
        throw new UnsupportedError('Unexpected ACL scope');
    }
  }
}

/// An ACL scope for an entity identified by a 'Google Storage ID'.
///
/// The [storageId] is a string of 64 hexadecimal digits that identifies a
/// specific Google account holder or a specific Google group.
class StorageIdScope extends AclScope {
  StorageIdScope(String storageId)
      : super._(AclScope._TYPE_STORAGE_ID, storageId);

  /// Google Storage ID.
  String get storageId => _id;
}

/// An ACL scope for an entity identified by an individual email address.
class AccountScope extends AclScope {
  AccountScope(String email): super._(AclScope._TYPE_ACCOUNT, email);

  /// Email address.
  String get email => _id;
}

/// An ACL scope for an entity identified by an Google Groups email.
class GroupScope extends AclScope {
  GroupScope(String group): super._(AclScope._TYPE_GROUP, group);

  /// Group name.
  String get group => _id;
}

/// An ACL scope for an entity identified by a domain name.
class DomainScope extends AclScope {
  DomainScope(String domain): super._(AclScope._TYPE_DOMAIN, domain);

  /// Domain name.
  String get domain => _id;
}

/// ACL scope for a all authenticated users.
class AllAuthenticatedScope extends AclScope {
  const AllAuthenticatedScope()
      : super._(AclScope._TYPE_ALL_AUTHENTICATED, null);
}

/// ACL scope for a all users.
class AllUsersScope extends AclScope {
  const AllUsersScope(): super._(AclScope._TYPE_ALL_USERS, null);
}

/// Permissions for individual scopes in an ACL.
class AclPermission {
  /// Provide read access.
  static const READ = const AclPermission._('READER');

  /// Provide write access.
  ///
  /// For objects this permission is the same as [FULL_CONTROL].
  static const WRITE = const AclPermission._('WRITER');

  /// Provide full control.
  ///
  /// For objects this permission is the same as [WRITE].
  static const FULL_CONTROL = const AclPermission._('OWNER');

  final String _id;

  const AclPermission._(this._id);

  String get _storageBucketRole => _id;

  String get _storageObjectRole => this == WRITE ? FULL_CONTROL._id : _id;
}

/// Definition of predefined ACLs.
///
/// There is a convenient way of referring to number of _predefined_ ACLs. These
/// predefined ACLs have explicit names, and can _only_ be used to set an ACL,
/// when either creating or updating a bucket or object. This set of predefined
/// ACLs are expanded on the server to their actual list of [AclEntry] objects.
/// When information is retreived on a bucket or object, this expanded list will
/// be present. For a description of these predefined ACLs see:
/// https://cloud.google.com/storage/docs/accesscontrol#extension.
class PredefinedAcl {
  String _name;
  PredefinedAcl._(this._name);

  /// Predefined ACL for the 'authenticated-read' ACL. Applies to both buckets
  /// and objects.
  static PredefinedAcl authenticatedRead =
      new PredefinedAcl._('authenticatedRead');

  /// Predefined ACL for the 'private' ACL. Applies to both buckets
  /// and objects.
  static PredefinedAcl private = new PredefinedAcl._('private');

  /// Predefined ACL for the 'project-private' ACL. Applies to both buckets
  /// and objects.
  static PredefinedAcl projectPrivate = new PredefinedAcl._('projectPrivate');

  /// Predefined ACL for the 'public-read' ACL. Applies to both buckets
  /// and objects.
  static PredefinedAcl publicRead = new PredefinedAcl._('publicRead');

  /// Predefined ACL for the 'public-read-write' ACL. Applies only to buckets.
  static PredefinedAcl publicReadWrite = new PredefinedAcl._('publicReadWrite');

  /// Predefined ACL for the 'bucket-owner-full-control' ACL. Applies only to
  /// objects.
  static PredefinedAcl bucketOwnerFullControl =
      new PredefinedAcl._('bucketOwnerFullControl');

  /// Predefined ACL for the 'bucket-owner-read' ACL. Applies only to
  /// objects.
  static PredefinedAcl bucketOwnerRead = new PredefinedAcl._('bucketOwnerRead');
}

/// Information on a bucket.
abstract class BucketInfo {
  /// Name of the bucket.
  String get bucketName;

  /// When this bucket was created.
  DateTime get created;
}

/// Access to Cloud Storage
abstract class Storage {
  /// List of required OAuth2 scopes for Cloud Storage operation.
  static const Scopes = const [storage.StorageApi.DevstorageFullControlScope];

  /// Initializes access to cloud storage.
  factory Storage(http.Client client, String project) = _StorageImpl;

  /// Create a cloud storage bucket.
  ///
  /// Creates a cloud storage bucket named [bucketName].
  ///
  /// The bucket ACL can be set by passing [predefinedAcl] or [acl]. If both
  /// are passed the entries from [acl] with be followed by the expansion of
  /// [predefinedAcl].
  ///
  /// Returns a [Future] which completes when the bucket has been created.
  Future createBucket(String bucketName,
                      {PredefinedAcl predefinedAcl, Acl acl});

  /// Delete a cloud storage bucket.
  ///
  /// Deletes the cloud storage bucket named [bucketName].
  ///
  /// If the bucket is not empty the operation will fail.
  ///
  /// The returned [Future] completes when the operation is finished.
  Future deleteBucket(String bucketName);

  /// Access bucket object operations.
  ///
  /// Instantiates a `Bucket` object refering to the bucket named [bucketName].
  ///
  /// When an object is created using the resulting `Bucket` an ACL will always
  /// be set. If the object creation does not pass any explicit ACL information
  /// a default ACL will be used.
  ///
  /// If the arguments [defaultPredefinedObjectAcl] or [defaultObjectAcl] are
  /// passed they define the default ACL. If both are passed the entries from
  /// [defaultObjectAcl] with be followed by the expansion of
  /// [defaultPredefinedObjectAcl] when an object is created.
  ///
  /// Otherwise the default object ACL attached to the bucket will be used.
  ///
  /// Returns a `Bucket` instance.
  Bucket bucket(String bucketName,
                {PredefinedAcl defaultPredefinedObjectAcl,
                 Acl defaultObjectAcl});

  /// Check whether a cloud storage bucket exists.
  ///
  /// Checks whether the bucket named [bucketName] exists.
  ///
  /// Returns a [Future] which completes with `true` if the bucket exists.
  Future<bool> bucketExists(String bucketName);

  /// Get information on a bucket
  ///
  /// Provide metadata information for bucket named [bucketName].
  ///
  /// Returns a [Future] which completes with a `BuckerInfo` object.
  Future<BucketInfo> bucketInfo(String bucketName);

  /// List names of all buckets.
  ///
  /// Returns a [Stream] of bucket names.
  Stream<String> listBucketNames();

  /// Start paging through names of all buckets.
  ///
  /// The maximum number of buckets in each page is specified in [pageSize].
  ///
  /// Returns a [Future] which completes with a `Page` object holding the
  /// first page. Use the `Page` object to move to the next page of buckets.
  Future<Page<String>> pageBucketNames({int pageSize: 50});

  /// Copy an object.
  ///
  /// Copy object [src] to object [dest].
  ///
  /// The names of [src] and [dest] must be absolute.
  Future copyObject(String src, String dest);
}

/// Information on a specific object.
///
/// This class provides access to information on an object. This includes
/// both the properties which are provided by Cloud Storage (such as the
/// MD5 hash) and the properties which can be changed (such as content type).
///
///  The properties provided by Cloud Storage are direct properties on this
///  object.
///
///  The mutable properties are properties on the `metadata` property.
abstract class ObjectInfo {
  /// Name of the object.
  String get name;

  /// Size of the data.
  int get size;

  /// When this object was updated.
  DateTime get updated;

  /// MD5 hash of the object.
  List<int> get md5Hash;

  /// CRC32c checksum, as described in RFC 4960.
  int get crc32CChecksum;

  /// URL for direct download.
  Uri get downloadLink;

  /// Object generation.
  ObjectGeneration get generation;

  /// Additional metadata.
  ObjectMetadata get metadata;
}

/// Generational information on an object.
abstract class ObjectGeneration {
  /// Object generation.
  String get objectGeneration;

  /// Metadata generation.
  int get metaGeneration;
}

/// Access to object metadata
abstract class ObjectMetadata {
  factory ObjectMetadata({Acl acl, String contentType, String contentEncoding,
      String cacheControl, String contentDisposition, String contentLanguage,
      Map<String, String> custom}) = _ObjectMetadata;
  /// ACL
  void set acl(Acl value);

  /// `Content-Type` for this object.
  String contentType;

  /// `Content-Encoding` for this object.
  String contentEncoding;

  /// `Cache-Control` for this object.
  String cacheControl;

  /// `Content-Disposition` for this object.
  String contentDisposition;

  /// `Content-Language` for this object.
  ///
  /// The value of this field must confirm to RFC 3282.
  String contentLanguage;

  /// Custom metadata.
  Map<String, String> custom;

  /// Create a copy of this object with some values replaces.
  ///
  /// TODO: This cannot be used to set values to null.
  ObjectMetadata replace({Acl acl, String contentType, String contentEncoding,
      String cacheControl, String contentDisposition, String contentLanguage,
      Map<String, String> custom});
}

/// Result from List objects in a bucket.
///
/// Listing operate like a directory listing, despite the object
/// namespace being flat.
///
/// See [Bucket.list] for information on how the hierarchical structure
/// is determined.
class BucketEntry {
  /// Whether this is information on an object.
  final bool isObject;

  /// Name of object or directory.
  final String name;

  BucketEntry._object(this.name) : isObject = true;

  BucketEntry._directory(this.name) : isObject = false;

  /// Whether this is a prefix.
  bool get isDirectory => !isObject;
}

/// Access to operations on a specific cloud storage buket.
abstract class Bucket {
  /// Name of this bucket.
  String get bucketName;

  /// Absolute name of an object in this bucket. This includes the gs:// prefix.
  String absoluteObjectName(String objectName);

  /// Create a new object.
  ///
  /// Create an object named [objectName] in the bucket.
  ///
  /// If an object named [objectName] already exists this object will be
  /// replaced.
  ///
  /// If the length of the data to write is known in advance this can be passed
  /// as [length]. This can help to optimize the upload process.
  ///
  /// Additional metadata on the object can be passed either through the
  /// `metadata` argument or through the specific named arguments
  /// (such as `contentType`). Values passed through the specific named
  /// arguments takes precedence over the values in `metadata`.
  ///
  /// If [contentType] is not passed the default value of
  /// `application/octet-stream` will be used.
  ///
  /// It is possible to at one of the predefined ACLs on the created object
  /// using the [predefinedAcl] argument. If the [metadata] argument contain a
  /// ACL as well, this ACL with be followed by the expansion of
  /// [predefinedAcl].
  ///
  /// Returns a `StreamSink` where the object content can be written. When
  /// The object content has been written the `StreamSink` completes with
  /// an `ObjectInfo` instance with the information on the object created.
  StreamSink<List<int>> write(String objectName,
      {int length, ObjectMetadata metadata,
       Acl acl, PredefinedAcl predefinedAcl, String contentType});

  /// Create an new object in the bucket with specified content.
  ///
  /// Writes [bytes] to the created object.
  ///
  /// See [write] for more information on the additional arguments.
  ///
  /// Returns a `Future` which completes with an `ObjectInfo` instance when
  /// the object is written.
  Future<ObjectInfo> writeBytes(String name, List<int> bytes,
      {ObjectMetadata metadata,
        Acl acl, PredefinedAcl predefinedAcl, String contentType});

  /// Read object content.
  ///
  /// TODO: More documentation
  Stream<List<int>> read(String objectName, {int offset: 0, int length});

  /// Lookup object metadata.
  ///
  /// TODO: More documentation
  Future<ObjectInfo> info(String name);

  /// Update object metadata.
  ///
  /// TODO: More documentation
  Future updateMetadata(String objectName, ObjectMetadata metadata);

  /// List objects in the bucket.
  ///
  /// Listing operates like a directory listing, despite the object
  /// namespace being flat. The character `/` is being used to separate
  /// object names into directory components.
  ///
  /// Retrieves a list of objects and directory components starting
  /// with [prefix].
  ///
  /// Returns a [Stream] of [BucketEntry]. Each element of the stream
  /// represents either an object or a directory component.
  Stream<BucketEntry> list({String prefix});

  /// Start paging through objects in the bucket.
  ///
  /// The maximum number of objects in each page is specified in [pageSize].
  ///
  /// See [list] for more information on the other arguments.
  ///
  /// Returns a `Future` which completes with a `Page` object holding the
  /// first page. Use the `Page` object to move to the next page.
  Future<Page<BucketEntry>> page({String prefix, int pageSize: 50});
}