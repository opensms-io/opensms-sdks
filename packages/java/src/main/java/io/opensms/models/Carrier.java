package io.opensms.models;

import java.util.List;

/** A mobile carrier. Fields the API omits decode as null. */
public final class Carrier {
    public String id;
    public String name;
    public List<String> mccMnc;
    public List<String> prefixes;
}
