//
//  SampleBoostApp
//  https://github.com/faithfracture/Apple-Boost-BuildScript
//
//  Distributed under the MIT License.
//

#import "ABBVegetable.h"

#import <boost/core/swap.hpp>

class CPPVegetable {
private:
    int seedsCount;
    int leavesCount;

public:
    CPPVegetable() {
        seedsCount = 12;
        leavesCount = 4;
    }

    void grow() {
        this->logState();

        NSLog(@"Vegetable is growing!");
        boost::swap(this->seedsCount, this->leavesCount);

        this->logState();
    }

    void logState() {
        NSLog(@"Seed count = %d, Leaves count = %d", seedsCount, leavesCount);
    }
};

@interface ABBVegetable () {
@private
    CPPVegetable *_vegetable;
}

@end

@implementation ABBVegetable

- (instancetype)init {
    self = [super init];
    if (self) {
        _vegetable = new CPPVegetable();
    }
    return self;
}

- (void)dealloc {
    delete _vegetable;
}


- (void)grow {
    _vegetable->grow();
}

@end
