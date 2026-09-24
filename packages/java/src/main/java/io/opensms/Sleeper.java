package io.opensms;

import java.time.Duration;

/**
 * Waits between retry attempts. The default uses {@link Thread#sleep(long)};
 * tests inject a zero-delay sleeper that records the requested delays.
 */
@FunctionalInterface
public interface Sleeper {

    /** The default sleeper, backed by {@link Thread#sleep(long)}. */
    Sleeper SYSTEM = d -> Thread.sleep(d.toMillis());

    /**
     * Wait for {@code delay}.
     *
     * @param delay how long to wait.
     * @throws InterruptedException when the thread is interrupted.
     */
    void sleep(Duration delay) throws InterruptedException;
}
