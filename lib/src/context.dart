import 'dart:async';
import 'dart:io' as io;

import 'package:meta/meta.dart';
import 'package:test/test.dart';
import 'package:tool_base/tool_base.dart';
import 'package:mockito/mockito.dart';
import 'common.dart';
import 'context_runner.dart';

/// Return the test logger. This assumes that the current Logger is a BufferLogger.
BufferLogger get testLogger => context.get<Logger>();

typedef ContextInitializer = void Function(AppContext testContext);

@isTest
void testUsingContext(
  String description,
  dynamic testMethod(), {
  Timeout timeout,
  Map<Type, Generator> overrides = const <Type, Generator>{},
  bool initializeFlutterRoot = true,
  String testOn,
  bool skip, // should default to `false`, but https://github.com/dart-lang/test/issues/545 doesn't allow this
}) {
  // Ensure we don't rely on the default [Config] constructor which will
  // leak a sticky $HOME/.flutter_settings behind!
  Directory configDir;
  tearDown(() {
    if (configDir != null) {
      tryToDelete(configDir);
      configDir = null;
    }
  });
  Config buildConfig(FileSystem fs) {
    configDir = fs.systemTempDirectory.createTempSync('flutter_config_dir_test.');
    final File settingsFile = fs.file(
      fs.path.join(configDir.path, '.flutter_settings')
    );
    return Config(settingsFile);
  }

  test(description, () async {
    await runInContext<dynamic>(() {
      return context.run<dynamic>(
        name: 'mocks',
        overrides: <Type, Generator>{
          Config: () => buildConfig(fs),
//          DeviceManager: () => FakeDeviceManager(),
//          Doctor: () => FakeDoctor(),
//          FlutterVersion: () => MockFlutterVersion(),
          HttpClient: () => MockHttpClient(),
//          IOSSimulatorUtils: () {
//            final MockIOSSimulatorUtils mock = MockIOSSimulatorUtils();
//            when(mock.getAttachedDevices()).thenAnswer((Invocation _) async => <IOSSimulator>[]);
//            return mock;
//          },
          OutputPreferences: () => OutputPreferences(showColor: false),
          Logger: () => BufferLogger(),
          OperatingSystemUtils: () => FakeOperatingSystemUtils(),
//          SimControl: () => MockSimControl(),
//          Usage: () => FakeUsage(),
//          XcodeProjectInterpreter: () => FakeXcodeProjectInterpreter(),
          FileSystem: () => const LocalFileSystemBlockingSetCurrentDirectory(),
          TimeoutConfiguration: () => const TimeoutConfiguration(),
//          PlistParser: () => FakePlistParser(),
        },
        body: () {
//          final String flutterRoot = getFlutterRoot();
          return runZoned<Future<dynamic>>(() {
            try {
              return context.run<dynamic>(
                // Apply the overrides to the test context in the zone since their
                // instantiation may reference items already stored on the context.
                overrides: overrides,
                name: 'test-specific overrides',
                body: () async {
                  if (initializeFlutterRoot) {
                    // Provide a sane default for the flutterRoot directory. Individual
                    // tests can override this either in the test or during setup.
//                    Cache.flutterRoot ??= flutterRoot;
                  }
                  return await testMethod();
                },
              );
            } catch (error) {
              _printBufferedErrors(context);
              rethrow;
            }
          }, onError: (dynamic error, StackTrace stackTrace) {
            io.stdout.writeln(error);
            io.stdout.writeln(stackTrace);
            _printBufferedErrors(context);
            throw error;
          });
        },
      );
    });
  }, timeout: timeout ?? const Timeout(Duration(seconds: 60)),
      testOn: testOn, skip: skip);
}

void _printBufferedErrors(AppContext testContext) {
  if (testContext.get<Logger>() is BufferLogger) {
    final BufferLogger bufferLogger = testContext.get<Logger>();
    if (bufferLogger.errorText.isNotEmpty)
      print(bufferLogger.errorText);
    bufferLogger.clear();
  }
}

class FakeOperatingSystemUtils implements OperatingSystemUtils {
  @override
  ProcessResult makeExecutable(File file) => null;

  @override
  void chmod(FileSystemEntity entity, String mode) { }

  @override
  File which(String execName) => null;

  @override
  List<File> whichAll(String execName) => <File>[];

  @override
  File makePipe(String path) => null;

  @override
  void zip(Directory data, File zipFile) { }

  @override
  void unzip(File file, Directory targetDirectory) { }

  @override
  bool verifyZip(File file) => true;

  @override
  void unpack(File gzippedTarFile, Directory targetDirectory) { }

  @override
  bool verifyGzip(File gzippedFile) => true;

  @override
  String get name => 'fake OS name and version';

  @override
  String get pathVarSeparator => ';';

  @override
  Future<int> findFreePort({bool ipv6 = false}) async => 12345;
}

class MockHttpClient extends Mock implements HttpClient {}

class LocalFileSystemBlockingSetCurrentDirectory extends LocalFileSystem {
  const LocalFileSystemBlockingSetCurrentDirectory();

  @override
  set currentDirectory(dynamic value) {
    throw 'fs.currentDirectory should not be set on the local file system during '
          'tests as this can cause race conditions with concurrent tests. '
          'Consider using a MemoryFileSystem for testing if possible or refactor '
          'code to not require setting fs.currentDirectory.';
  }
}
