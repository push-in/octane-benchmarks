<?php

// Loaded with --bootstrap when OCTANE_DRIVER=pam; writes the cross-check report.
require __DIR__.'/../../vendor/autoload.php';

register_shutdown_function(static function (): void {
    if (! is_string($report = getenv('PAM_OCTANE_MISMATCH_REPORT')) || $report === '') {
        return;
    }

    file_put_contents($report, json_encode([
        'exchanges' => \Laravel\Octane\Tests\PamReadiness\PamFakeClient::$exchanges,
        'mismatches' => \Laravel\Octane\Tests\PamReadiness\PamFakeClient::$mismatches,
    ], JSON_PRETTY_PRINT));
});
