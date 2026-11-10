<?php

namespace Laravel\Octane\Tests\PamReadiness;

use Illuminate\Foundation\Application;
use Illuminate\Http\Request;
use Laravel\Octane\OctaneResponse;
use Laravel\Octane\Pam\PamClient;
use Laravel\Octane\RequestContext;
use Laravel\Octane\Testing\Fakes\FakeClient;
use Symfony\Component\HttpFoundation\BinaryFileResponse;
use Symfony\Component\HttpFoundation\StreamedResponse;
use Throwable;

/**
 * Drop-in replacement for Octane's FakeClient that pushes every request and
 * response of the upstream suite through Laravel\Octane\Pam\PamClient.
 *
 * Upstream assertions keep running on the original response objects, while
 * each response PamClient writes through the SAPI (status, headers, cookies,
 * body) is compared with what Laravel produced. Any difference is recorded
 * and reported by bootstrap.php.
 */
class PamFakeClient extends FakeClient
{
    public static array $mismatches = [];

    public static int $exchanges = 0;

    protected PamClient $pam;

    public function __construct(array $requests)
    {
        parent::__construct($requests);

        $this->pam = new PamClient;
    }

    public function marshalRequest(RequestContext $context): array
    {
        $original = $context->request;

        // PAM fills PHP's request globals before it invokes the worker...
        $_GET = $original->query->all();
        $_POST = $original->request->all();
        $_COOKIE = $original->cookies->all();
        $_FILES = [];
        $_SERVER = $original->server->all();

        [$marshaled] = $this->pam->marshalRequest(new RequestContext);

        foreach ([
            'method' => [$original->getMethod(), $marshaled->getMethod()],
            'uri' => [$original->getRequestUri(), $marshaled->getRequestUri()],
            'host' => [$original->getHttpHost(), $marshaled->getHttpHost()],
            'query' => [$original->query->all(), $marshaled->query->all()],
            'input' => [$original->request->all(), $marshaled->request->all()],
            'cookies' => [$original->cookies->all(), $marshaled->cookies->all()],
        ] as $aspect => [$expected, $actual]) {
            if ($expected !== $actual) {
                static::$mismatches[] = "request {$aspect}: ".json_encode([$expected, $actual]);
            }
        }

        return parent::marshalRequest($context);
    }

    public function respond(RequestContext $context, OctaneResponse $octaneResponse): void
    {
        parent::respond($context, $octaneResponse);

        static::$exchanges++;

        $source = $octaneResponse->response;

        // Upstream asserts on the unsent stream callback; do not consume it here...
        if ($source instanceof StreamedResponse || $source instanceof BinaryFileResponse) {
            return;
        }

        [$status, $headers, $body] = $this->capture(fn () => $this->pam->respond($context, $octaneResponse));

        $expected = ($octaneResponse->outputBuffer ?? '').$source->getContent();

        if ($status !== $source->getStatusCode() || $body !== $expected) {
            static::$mismatches[] = sprintf('response %s: status %d/%d body %s', $context->request->getRequestUri(),
                $source->getStatusCode(), $status, $body === $expected ? 'equal' : 'differs');
        }

        foreach ($source->headers->getCookies() as $cookie) {
            if (! in_array('Set-Cookie: '.$cookie, $headers, true)) {
                static::$mismatches[] = 'cookie lost: '.$cookie->getName();
            }
        }
    }

    public function error(Throwable $e, Application $app, Request $request, RequestContext $context): void
    {
        parent::error($e, $app, $request, $context);

        [$status] = $this->capture(fn () => $this->pam->error($e, $app, $request, $context));

        if ($status !== 500) {
            static::$mismatches[] = 'error response is not 500';
        }
    }

    /**
     * Run the callback and return what it wrote through the SAPI.
     */
    protected function capture(callable $callback): array
    {
        header_remove();
        @http_response_code(200);

        ob_start();

        try {
            $callback();
        } finally {
            $body = ob_get_clean();
        }

        return [http_response_code(), headers_list(), $body];
    }
}
