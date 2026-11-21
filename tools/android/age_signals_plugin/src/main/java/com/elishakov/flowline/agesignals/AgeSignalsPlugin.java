package com.elishakov.flowline.agesignals;

import android.app.Activity;
import android.util.Log;

import androidx.annotation.NonNull;

import com.google.android.play.agesignals.AgeSignalsAccessRequest;
import com.google.android.play.agesignals.AgeSignalsManager;
import com.google.android.play.agesignals.AgeSignalsManagerFactory;
import com.google.android.play.agesignals.AgeSignalsRequest;
import com.google.android.play.agesignals.ApplicableAgeFeaturesRequest;
import com.google.android.play.agesignals.model.AgeSignalsStatus;
import com.google.android.play.agesignals.model.ApplicableAgeFeature;

import org.godotengine.godot.Godot;
import org.godotengine.godot.plugin.GodotPlugin;
import org.godotengine.godot.plugin.SignalInfo;
import org.godotengine.godot.plugin.UsedByGodot;

import java.util.Collections;
import java.util.Set;

/**
 * Google Play Age Signals (age assurance laws, e.g. California AB 1043 and
 * Brazil's Digital ECA, from January 2027).
 *
 * FLOWLINE is the same 4+ game for every age: no ads, purchases, accounts,
 * chat or data collection. So it only does what those laws ask of an app:
 * where Play says mandatory age sharing applies to this user, it requests
 * the age signal (Play shows its own prompt if needed). The age range is not
 * stored, sent anywhere or used for anything else (Play's API terms allow it
 * only for age-appropriate experiences). Elsewhere it does nothing at all.
 */
public class AgeSignalsPlugin extends GodotPlugin {
    private static final String TAG = "FlowlineAgeSignals";
    private static final SignalInfo DONE = new SignalInfo("age_signals_done", String.class);
    private boolean running = false;

    public AgeSignalsPlugin(Godot godot) {
        super(godot);
    }

    @NonNull
    @Override
    public String getPluginName() {
        return "FlowlineAgeSignals";
    }

    @NonNull
    @Override
    public Set<SignalInfo> getPluginSignals() {
        return Collections.singleton(DONE);
    }

    /** Called once per launch from the game. Never throws; always emits age_signals_done. */
    @UsedByGodot
    public void check() {
        if (running) {
            return;
        }
        running = true;
        final Activity activity = getActivity();
        if (activity == null) {
            finish("no_activity");
            return;
        }
        runOnUiThread(() -> {
            try {
                final AgeSignalsManager manager = AgeSignalsManagerFactory.create(activity.getApplicationContext());
                manager.getApplicableAgeFeatures(ApplicableAgeFeaturesRequest.builder().build())
                        .addOnSuccessListener(features -> {
                            Set<Integer> f = features.features();
                            if (f == null || !f.contains(ApplicableAgeFeature.MANDATORY_SHARING)) {
                                finish("not_required");
                                return;
                            }
                            requestAccess(manager, activity);
                        })
                        .addOnFailureListener(e -> finish("error: " + e.getMessage()));
            } catch (Throwable t) {
                finish("error: " + t);
            }
        });
    }

    private void requestAccess(AgeSignalsManager manager, Activity activity) {
        AgeSignalsAccessRequest request = AgeSignalsAccessRequest.builder().setActivity(activity).build();
        manager.requestAgeSignalsAccess(request)
                .addOnSuccessListener(access -> {
                    Integer status = access.ageSignalsStatus();
                    if (status != null && status == AgeSignalsStatus.SHARED) {
                        manager.checkAgeSignals(AgeSignalsRequest.builder().build())
                                // Received and deliberately not kept: the game is the same for all ages.
                                .addOnSuccessListener(result -> finish("shared"))
                                .addOnFailureListener(e -> finish("error: " + e.getMessage()));
                    } else if (status != null && status == AgeSignalsStatus.VERIFICATION_REQUIRED) {
                        finish("verification_required");
                    } else {
                        finish("not_shared");
                    }
                })
                .addOnFailureListener(e -> finish("error: " + e.getMessage()));
    }

    private void finish(String status) {
        running = false;
        Log.i(TAG, "age signals: " + status);
        emitSignal(DONE.getName(), status);
    }
}
