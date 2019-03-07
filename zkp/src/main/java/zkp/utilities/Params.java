package zkp.utilities;

import edu.stanford.cs.crypto.efficientct.GeneratorParams;
import edu.stanford.cs.crypto.efficientct.algebra.BN128Group;
import edu.stanford.cs.crypto.efficientct.algebra.BN128Point;

public class Params {

    private static final BN128Group group = new BN128Group();

    private static GeneratorParams<BN128Point> zetherParams = GeneratorParams.generateParams(64, group);
    private static GeneratorParams<BN128Point> burnParams = GeneratorParams.generateParams(32, group);

    public static BN128Group getGroup() { return group; }

    public static BN128Point zetherGenerator() {
        return zetherParams.getBase().g;
    }

    public static BN128Point burnGenerator() {
        return burnParams.getBase().g;
    }

    public static GeneratorParams<BN128Point> getZetherParams() {
        return zetherParams;
    }

    public static GeneratorParams<BN128Point> getBurnParams() {
        return burnParams;
    }

}
