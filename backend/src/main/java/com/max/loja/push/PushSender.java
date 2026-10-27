package com.max.loja.push;

import java.util.Map;

/** Envia uma notificação push para um celular. */
public interface PushSender {

    enum Result { SENT, INVALID_TOKEN, FAILED, DISABLED }

    Result send(String token, String title, String body, Map<String, String> data);
}
