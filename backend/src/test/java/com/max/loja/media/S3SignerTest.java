package com.max.loja.media;

import static org.assertj.core.api.Assertions.assertThat;

import java.net.URI;
import java.util.Map;

import org.junit.jupiter.api.Test;

class S3SignerTest {

    /** Exemplo "GET Object" da documentação da AWS (Signature Version 4, header Authorization). */
    @Test
    void matchesAwsDocumentationExample() {
        String emptyHash = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855";
        String auth = S3Signer.authorization("GET", URI.create("https://examplebucket.s3.amazonaws.com/test.txt"),
                Map.of("host", "examplebucket.s3.amazonaws.com", "range", "bytes=0-9",
                        "x-amz-content-sha256", emptyHash, "x-amz-date", "20130524T000000Z"),
                emptyHash, "us-east-1", "AKIAIOSFODNN7EXAMPLE", "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY");

        assertThat(auth).isEqualTo("AWS4-HMAC-SHA256 Credential=AKIAIOSFODNN7EXAMPLE/20130524/us-east-1/s3/aws4_request,"
                + "SignedHeaders=host;range;x-amz-content-sha256;x-amz-date,"
                + "Signature=f0e8bdb87c964420e857bd35b5d6ed310bd44f0170aba48dd91039c6036bdb41");
    }

    @Test
    void sha256OfEmptyPayload() {
        assertThat(S3Signer.sha256Hex(new byte[0]))
                .isEqualTo("e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855");
    }

    @Test
    void encodesOnlyUnsafeCharacters() {
        assertThat(S3Signer.encodeKey("salons/12/abc_t.jpg")).isEqualTo("salons/12/abc_t.jpg");
        assertThat(S3Signer.encodeKey("a b/ç.jpg")).isEqualTo("a%20b/%C3%A7.jpg");
    }
}
