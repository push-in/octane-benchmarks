<?php

// Benchmark and behavior routes, loaded by bootstrap/app.php without the web
// middleware group (no session, no CSRF), the same for every server.

use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Route;

Route::prefix('_r')->group(function () {
    Route::get('/hello', fn () => 'Hello World!');
    Route::get('/json', fn () => response()->json(['message' => 'Hello World!', 'n' => 42]));
    Route::get('/db', fn () => response()->json(
        DB::table('users')->where('id', random_int(1, 100))->first(),
    ));
    Route::get('/view', fn () => view('bench', ['items' => range(1, 20)]));
    // The same page, cacheable by a shared cache for 60 s (scripts/page-cache.sh).
    Route::get('/view-cached', fn () => response(view('bench', ['items' => range(1, 20)]))
        ->header('Cache-Control', 'public, s-maxage=60'));

    Route::get('/pid', fn () => response()->json(['pid' => getmypid()]));

    Route::get('/sleep/{ms}', function (int $ms) {
        usleep($ms * 1000);

        return response()->json(['slept' => $ms]);
    });

    // Symfony's Response::send() sends a raw `HTTP/1.1 200 OK` status line.
    Route::get('/send', fn () => response('sent')->send());

    // A request whose upload is on disk when the request timeout cuts it.
    Route::post('/upload-sleep/{ms}', function (int $ms) {
        usleep($ms * 1000);

        return response()->json(['slept' => $ms]);
    });

    Route::post('/upload', function (Request $request) {
        $file = $request->file('file');

        if ($file === null || ! $file->isValid()) {
            return response()->json(['ok' => false, 'error' => $file?->getError()], 422);
        }

        $sha256 = hash_file('sha256', $file->getRealPath());
        $moved = $file->move(storage_path('app'), 'upload.bin');
        $movedSha256 = hash_file('sha256', $moved->getPathname());
        $size = filesize($moved->getPathname());
        @unlink($moved->getPathname());

        return response()->json([
            'ok' => true,
            'size' => $size,
            'sha256' => $sha256,
            'moved_sha256' => $movedSha256,
            'memory_limit' => ini_get('memory_limit'),
            'php_peak_bytes' => memory_get_peak_usage(true),
            'pid' => getmypid(),
        ]);
    });
});
